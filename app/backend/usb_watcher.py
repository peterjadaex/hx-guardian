#!/usr/bin/env python3
"""
HX Guardian USB Watcher — system-level USB enforcement daemon.

Runs as root via launchd. Polls USB device state every 5 seconds,
cross-checks each new arrival against the HX Guardian whitelist in SQLite,
and for any unauthorized device:
  1. Logs a USB_UNAUTHORIZED_DEVICE entry to the audit_log table
  2. Sends a macOS system notification to the console user
  3. Attempts to eject any storage volumes attached to the device

Unauthorized devices that are already connected when the daemon starts are
logged once on startup. Subsequent polls only log *new* arrivals so the
audit trail is not spammed while the device remains plugged in.
"""
import json
import logging
import plistlib
import sqlite3
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).resolve().parent
DB_PATH = SCRIPT_DIR.parent / "data" / "hxguardian.db"
POLL_INTERVAL = 5       # seconds between USB device polls
WHITELIST_REFRESH = 30  # seconds between whitelist reloads from DB
LOG_FILE = "/var/log/hxguardian_usb.log"

USB_UNAUTHORIZED_DEVICE = "USB_UNAUTHORIZED_DEVICE"

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
    ],
)
log = logging.getLogger(__name__)


# ── USB enumeration ───────────────────────────────────────────────────────────

def _parse_usb_items(items: list, out: list) -> None:
    for item in items:
        if not isinstance(item, dict):
            continue
        name = item.get("_name", "")
        vendor = item.get("manufacturer", "")
        product_id = item.get("product_id", "")
        serial = item.get("serial_num", "")

        # Collect BSD disk names for storage volumes so we can eject them
        bsd_names: list[str] = []
        for media in item.get("Media", []):
            if isinstance(media, dict):
                bsd = media.get("bsd_name", "")
                if bsd:
                    bsd_names.append(bsd)

        if name:
            out.append({
                "name": name,
                "vendor": vendor,
                "product_id": product_id,
                "serial": serial,
                "bsd_names": bsd_names,
            })

        for key in ("_items", "hub_device"):
            sub = item.get(key)
            if isinstance(sub, list):
                _parse_usb_items(sub, out)


def get_usb_devices() -> list[dict]:
    """Return a list of currently connected USB devices."""
    try:
        result = subprocess.run(
            ["/usr/sbin/system_profiler", "SPUSBDataType", "-json"],
            capture_output=True, text=True, timeout=10,
        )
        data = json.loads(result.stdout)
        devices: list[dict] = []
        for entry in data.get("SPUSBDataType", []):
            _parse_usb_items(entry.get("_items", []), devices)
        return devices
    except Exception as exc:
        log.error("Failed to enumerate USB devices: %s", exc)
        return []


def device_key(dev: dict) -> str:
    """Stable identity key for a device — prefer serial, fall back to product_id+name."""
    if dev.get("serial"):
        return f"serial:{dev['serial']}"
    if dev.get("product_id"):
        return f"pid:{dev['product_id']}:{dev.get('name', '')}"
    return f"name:{dev.get('name', '')}"


# ── Whitelist ─────────────────────────────────────────────────────────────────

def load_whitelist() -> list[dict]:
    """Read the USB whitelist directly from SQLite."""
    if not DB_PATH.exists():
        return []
    try:
        con = sqlite3.connect(str(DB_PATH))
        con.row_factory = sqlite3.Row
        rows = con.execute(
            "SELECT product_id, serial, volume_uuid FROM usb_whitelist"
        ).fetchall()
        con.close()
        return [dict(r) for r in rows]
    except Exception as exc:
        log.error("Failed to load whitelist: %s", exc)
        return []


def get_volume_uuid(bsd_name: str) -> str:
    """Return the VolumeUUID for a BSD disk name, or empty string on failure."""
    try:
        r = subprocess.run(
            ["diskutil", "info", "-plist", f"/dev/{bsd_name}"],
            capture_output=True, timeout=5,
        )
        info = plistlib.loads(r.stdout)
        return info.get("VolumeUUID", "")
    except Exception:
        return ""


def is_whitelisted(dev: dict, whitelist: list[dict], volume_uuid: str = "") -> bool:
    for entry in whitelist:
        checks = []
        if entry["product_id"]:
            checks.append(dev.get("product_id") == entry["product_id"])
        if entry["serial"]:
            checks.append(dev.get("serial") == entry["serial"])
        if entry.get("volume_uuid"):
            checks.append(volume_uuid == entry["volume_uuid"])
        if checks and all(checks):
            return True
    return False


# ── Enforcement actions ───────────────────────────────────────────────────────

def eject_storage(bsd_names: list[str]) -> list[str]:
    """Force-eject storage volumes by BSD disk name. Returns names that succeeded."""
    ejected = []
    for bsd in bsd_names:
        disk = f"/dev/{bsd}" if not bsd.startswith("/dev/") else bsd
        result = subprocess.run(
            ["diskutil", "eject", disk],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            ejected.append(bsd)
            log.info("Ejected unauthorized storage volume: %s", disk)
        else:
            log.warning("Could not eject %s: %s", disk, result.stderr.strip())
    return ejected


def notify_user(device_name: str) -> None:
    """Send a macOS notification to the console user (works when running as root)."""
    try:
        # Get UID of the current console user
        uid_result = subprocess.run(
            ["stat", "-f", "%u", "/dev/console"],
            capture_output=True, text=True,
        )
        uid = uid_result.stdout.strip()
        if not uid:
            return
        script = (
            f'display notification "Device: {device_name}" '
            f'with title "⚠ Unauthorized USB Device Blocked" '
            f'sound name "Basso"'
        )
        subprocess.run(
            ["launchctl", "asuser", uid, "osascript", "-e", script],
            capture_output=True, timeout=5,
        )
    except Exception as exc:
        log.warning("Could not send notification: %s", exc)


def log_to_audit(dev: dict, ejected: list[str]) -> None:
    """Write a USB_UNAUTHORIZED_DEVICE record to the audit_log table."""
    if not DB_PATH.exists():
        return
    try:
        detail = json.dumps({
            "name": dev.get("name"),
            "vendor": dev.get("vendor"),
            "product_id": dev.get("product_id"),
            "serial": dev.get("serial"),
            "ejected_volumes": ejected,
        })
        con = sqlite3.connect(str(DB_PATH))
        con.execute(
            """
            INSERT INTO audit_log (ts, action, target, detail_json, operator, source_ip)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                datetime.utcnow().isoformat(),
                USB_UNAUTHORIZED_DEVICE,
                dev.get("name", "unknown"),
                detail,
                "usb_watcher",
                "system",
            ),
        )
        con.commit()
        con.close()
    except Exception as exc:
        log.error("Failed to write audit log: %s", exc)


# ── Main loop ─────────────────────────────────────────────────────────────────

def _filter_unauthorized_bsds(dev: dict, whitelist: list[dict]) -> list[str]:
    """Return bsd_names that are not individually whitelisted by volume UUID."""
    unauthorized = []
    for bsd in dev.get("bsd_names", []):
        uuid = get_volume_uuid(bsd)
        if not is_whitelisted(dev, whitelist, volume_uuid=uuid):
            unauthorized.append(bsd)
        else:
            log.info("Whitelisted volume (UUID match) on %s: %s", dev.get("name"), bsd)
    return unauthorized


def handle_unauthorized(dev: dict, whitelist: list[dict]) -> None:
    name = dev.get("name", "Unknown Device")
    log.warning(
        "UNAUTHORIZED USB device connected: %s (vendor=%s product_id=%s serial=%s)",
        name, dev.get("vendor"), dev.get("product_id"), dev.get("serial"),
    )
    bsds_to_eject = _filter_unauthorized_bsds(dev, whitelist)
    ejected = eject_storage(bsds_to_eject)
    log_to_audit(dev, ejected)
    notify_user(name)


def main() -> None:
    log.info("HX Guardian USB Watcher starting (DB: %s)", DB_PATH)

    whitelist: list[dict] = []
    whitelist_loaded_at: float = 0.0

    # Devices seen so far — tracked to avoid re-alerting on the same connection
    seen_keys: set[str] = set()
    # Unauthorized devices already alerted this session
    alerted_keys: set[str] = set()
    # BSD names already ejected — tracks volumes so re-inserted cards are ejected again
    ejected_bsds: set[str] = set()

    while True:
        now = time.monotonic()

        # Refresh whitelist periodically
        if now - whitelist_loaded_at >= WHITELIST_REFRESH:
            whitelist = load_whitelist()
            whitelist_loaded_at = now
            log.debug("Whitelist refreshed: %d entries", len(whitelist))

        current_devices = get_usb_devices()
        current_keys = {device_key(d) for d in current_devices}

        # Devices that just appeared since the last poll
        new_keys = current_keys - seen_keys

        for dev in current_devices:
            k = device_key(dev)
            if k not in new_keys:
                continue  # not new this cycle
            if is_whitelisted(dev, whitelist):
                log.info("Whitelisted USB device connected: %s", dev.get("name"))
            elif k not in alerted_keys:
                handle_unauthorized(dev, whitelist)
                alerted_keys.add(k)
                ejected_bsds.update(dev.get("bsd_names", []))

        # Re-eject volumes on already-alerted devices (handles SD card reinserted
        # into the same reader — the reader never leaves seen_keys so it never
        # appears as "new", but its storage volume can come back)
        for dev in current_devices:
            k = device_key(dev)
            if k not in alerted_keys:
                continue
            new_bsds = [b for b in dev.get("bsd_names", []) if b not in ejected_bsds]
            if new_bsds:
                # Filter out any volumes that are now individually whitelisted by UUID
                unauthorized_bsds = [
                    b for b in new_bsds
                    if not is_whitelisted(dev, whitelist, volume_uuid=get_volume_uuid(b))
                ]
                if unauthorized_bsds:
                    log.warning(
                        "Unauthorized volume reinserted on %s: %s",
                        dev.get("name"), unauthorized_bsds,
                    )
                    ejected = eject_storage(unauthorized_bsds)
                    ejected_bsds.update(ejected)
                    if ejected:
                        log_to_audit(dev, ejected)
                        notify_user(dev.get("name", "Unknown Device"))
                ejected_bsds.update(new_bsds)  # mark all new bsds seen regardless

        # Clean up tracking sets for devices/volumes no longer present
        alerted_keys &= current_keys
        current_bsds = {b for d in current_devices for b in d.get("bsd_names", [])}
        ejected_bsds &= current_bsds
        seen_keys = current_keys

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log.info("USB Watcher stopped.")
