"""
Device router — macOS device status and connection monitoring.
GET /api/device/status       → OS version, SIP, FileVault, Gatekeeper, Secure Boot
GET /api/device/connections  → USB devices, Bluetooth, network interfaces
GET /api/preflight           → signing readiness check
"""
import asyncio
import json
import logging
import plistlib
import re
import subprocess
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional

import core.audit as audit
from core.auth import verify_token
from core.database import get_db
from core.models import DeviceSnapshot, UsbWhitelist

USB_WHITELIST_ADDED = "USB_WHITELIST_ADDED"
USB_WHITELIST_REMOVED = "USB_WHITELIST_REMOVED"


class UsbWhitelistCreate(BaseModel):
    name: str
    vendor: Optional[str] = None
    product_id: Optional[str] = None
    serial: Optional[str] = None
    volume_uuid: Optional[str] = None
    notes: Optional[str] = None

logger = logging.getLogger(__name__)
router = APIRouter(tags=["device"])


async def _run(cmd: list[str], timeout: float = 10.0) -> tuple[str, str, int]:
    """Run a command and return (stdout, stderr, returncode)."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        return stdout.decode("utf-8", errors="replace"), stderr.decode("utf-8", errors="replace"), proc.returncode
    except asyncio.TimeoutError:
        logger.warning("Command timed out: %s", cmd)
        return "", "timeout", -1
    except Exception as e:
        return "", str(e), -1


async def collect_device_status() -> dict:
    """Collect key device security posture indicators."""
    results = await asyncio.gather(
        _run(["/usr/bin/sw_vers"]),
        _run(["/usr/bin/csrutil", "status"]),
        _run(["/usr/bin/fdesetup", "status"]),
        _run(["/usr/sbin/spctl", "--status"]),
        _run(["/usr/bin/defaults", "read", "/Library/Preferences/com.apple.security.firewall", "EnableFirewall"]),
        _run(["/usr/sbin/nvram", "94b73556-2197-4702-82a8-3e1337dafbfb:AppleSecureBootPolicy"]),
        _run(["/usr/sbin/system_profiler", "SPHardwareDataType", "-json"]),
        _run(["/bin/uptime"]),
        return_exceptions=True,
    )

    sw_out, _, _ = results[0]
    sip_out, _, _ = results[1]
    fv_out, _, _ = results[2]
    gk_out, _, _ = results[3]
    fw_out, _, _ = results[4]
    sb_out, _, _ = results[5]
    hw_out, _, _ = results[6]
    uptime_out, _, _ = results[7]

    # Parse sw_vers
    os_version = build = ""
    for line in sw_out.splitlines():
        if "ProductVersion" in line:
            os_version = line.split(":")[1].strip()
        elif "BuildVersion" in line:
            build = line.split(":")[1].strip()

    # SIP — match exact "status: enabled." to exclude partial/custom configs
    # e.g. "enabled (Custom Configuration)." would not match and correctly returns False
    sip_enabled = "status: enabled." in sip_out.lower()

    # FileVault
    fv_on = "On" in fv_out or "FileVault is On" in fv_out

    # Gatekeeper
    gk_on = "enabled" in gk_out.lower()

    # Firewall
    try:
        fw_on = fw_out.strip() == "1"
    except Exception:
        fw_on = None

    # Secure boot
    secure_boot = "unknown"
    if "FullSecurityEnabled" in sb_out or "\x02" in sb_out:
        secure_boot = "full"
    elif "MediumSecurityEnabled" in sb_out:
        secure_boot = "medium"
    elif "NoSecurityEnabled" in sb_out:
        secure_boot = "none"

    # Hardware model and serial
    hw_model = serial = ""
    try:
        hw_data = json.loads(hw_out)
        hw_items = hw_data.get("SPHardwareDataType", [{}])
        if hw_items:
            hw_model = hw_items[0].get("machine_name", "")
            serial = hw_items[0].get("serial_number", "")
    except Exception:
        pass

    # Uptime
    uptime_secs = None
    m = re.search(r"up\s+(?:(\d+)\s+days?,\s+)?(\d+):(\d+)", uptime_out)
    if m:
        days = int(m.group(1) or 0)
        hours = int(m.group(2) or 0)
        mins = int(m.group(3) or 0)
        uptime_secs = days * 86400 + hours * 3600 + mins * 60

    return {
        "os_version": os_version,
        "build_version": build,
        "sip_enabled": sip_enabled,
        "filevault_on": fv_on,
        "gatekeeper_on": gk_on,
        "firewall_on": fw_on,
        "secure_boot": secure_boot,
        "hardware_model": hw_model,
        "serial_number": serial,
        "uptime_secs": uptime_secs,
        "captured_at": datetime.utcnow().isoformat(),
    }


async def collect_connections() -> dict:
    """Collect USB devices, Bluetooth state, network interfaces, and open connections."""
    results = await asyncio.gather(
        _run(["/usr/sbin/system_profiler", "SPUSBDataType", "-json"]),
        _run(["/usr/sbin/system_profiler", "SPBluetoothDataType", "-json"]),
        _run(["/sbin/ifconfig", "-a"]),
        _run(["/usr/sbin/netstat", "-an", "-p", "tcp"]),
        return_exceptions=True,
    )

    usb_out, _, _ = results[0]
    bt_out, _, _ = results[1]
    ifconfig_out, _, _ = results[2]
    netstat_out, _, _ = results[3]

    # Parse USB
    usb_devices = []
    usb_volumes = []
    try:
        usb_data = json.loads(usb_out)
        def _parse_usb(items):
            for item in items:
                if isinstance(item, dict):
                    name = item.get("_name", "")
                    vendor = item.get("manufacturer", "")
                    product_id = item.get("product_id", "")
                    serial = item.get("serial_num", "")
                    if name:
                        usb_devices.append({
                            "name": name,
                            "vendor": vendor,
                            "product_id": product_id,
                            "serial": serial,
                        })
                    for media in item.get("Media", []):
                        if not isinstance(media, dict):
                            continue
                        for vol in media.get("volumes", []):
                            if not isinstance(vol, dict):
                                continue
                            mount_point = vol.get("mount_point", "")
                            if not mount_point:
                                continue
                            bsd_name = vol.get("bsd_name", "")
                            volume_uuid = ""
                            if bsd_name:
                                try:
                                    r = subprocess.run(
                                        ["diskutil", "info", "-plist", f"/dev/{bsd_name}"],
                                        capture_output=True, timeout=5,
                                    )
                                    info = plistlib.loads(r.stdout)
                                    volume_uuid = info.get("VolumeUUID", "")
                                except Exception:
                                    pass
                            usb_volumes.append({
                                "vol_name":          vol.get("_name", ""),
                                "bsd_name":          bsd_name,
                                "mount_point":       mount_point,
                                "file_system":       vol.get("file_system", ""),
                                "size":              vol.get("size", ""),
                                "volume_uuid":       volume_uuid,
                                "parent_name":       name,
                                "parent_vendor":     vendor,
                                "parent_product_id": product_id,
                                "parent_serial":     serial,
                            })
                    for key in ["_items", "hub_device"]:
                        if key in item:
                            sub = item[key]
                            if isinstance(sub, list):
                                _parse_usb(sub)
        for entry in usb_data.get("SPUSBDataType", []):
            _parse_usb(entry.get("_items", []))
    except Exception:
        pass

    # Parse Bluetooth
    bt_enabled = False
    bt_devices = []
    try:
        bt_data = json.loads(bt_out)
        for entry in bt_data.get("SPBluetoothDataType", []):
            controller = entry.get("controller_properties", {})
            # macOS 14+: controller_state; older: controller_bluetoothEnabled
            state = controller.get("controller_state", controller.get("controller_bluetoothEnabled", ""))
            bt_enabled = state.lower() in ("attrib_on", "attrib_yes")

            # macOS 14+: devices split into device_connected / device_not_connected
            # Older macOS: device_title (with per-device isconnected/ispaired flags)
            for dev_entry in entry.get("device_connected", []):
                for dev_name, dev_props in dev_entry.items():
                    bt_devices.append({
                        "name": dev_name,
                        "connected": True,
                        "paired": True,
                        "type": dev_props.get("device_minorType", dev_props.get("device_minorClassOfDevice_string", "")),
                    })
            for dev_entry in entry.get("device_not_connected", []):
                for dev_name, dev_props in dev_entry.items():
                    bt_devices.append({
                        "name": dev_name,
                        "connected": False,
                        "paired": True,
                        "type": dev_props.get("device_minorType", dev_props.get("device_minorClassOfDevice_string", "")),
                    })
            # Fallback for older macOS structure
            for dev_entry in entry.get("device_title", []):
                for dev_name, dev_props in dev_entry.items():
                    bt_devices.append({
                        "name": dev_name,
                        "connected": dev_props.get("device_isconnected", "").lower() == "attrib_yes",
                        "paired": dev_props.get("device_ispaired", "").lower() == "attrib_yes",
                        "type": dev_props.get("device_minorClassOfDevice_string", ""),
                    })
    except Exception:
        pass

    # Parse interfaces
    interfaces = []
    current = None
    for line in ifconfig_out.splitlines():
        if not line.startswith(" ") and not line.startswith("\t"):
            if current:
                interfaces.append(current)
            parts = line.split(":")
            current = {"name": parts[0], "flags": parts[1] if len(parts) > 1 else "", "ip": [], "status": "down"}
        elif current:
            if "inet " in line:
                m = re.search(r"inet (\d+\.\d+\.\d+\.\d+)", line)
                if m:
                    current["ip"].append(m.group(1))
                    current["status"] = "up"
            elif "status: active" in line:
                current["status"] = "active"
    if current:
        interfaces.append(current)

    # Parse established connections
    established = []
    for line in netstat_out.splitlines():
        if "ESTABLISHED" in line:
            parts = line.split()
            if len(parts) >= 5:
                established.append({
                    "proto": parts[0],
                    "local": parts[3],
                    "remote": parts[4],
                    "state": parts[5] if len(parts) > 5 else "",
                })

    internet_detected = any(
        not conn["remote"].startswith(("127.", "::1", "0.0.0.0"))
        for conn in established
    )

    return {
        "usb_devices": usb_devices,
        "usb_volumes": usb_volumes,
        "bluetooth_enabled": bt_enabled,
        "bluetooth_devices": bt_devices,
        "network_interfaces": interfaces,
        "established_connections": established,
        "internet_detected": internet_detected,
        "captured_at": datetime.utcnow().isoformat(),
    }


@router.get("/api/device/status")
async def get_device_status(
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    status = await collect_device_status()

    # Store snapshot
    snapshot = DeviceSnapshot(
        captured_at=datetime.utcnow(),
        os_version=status.get("os_version"),
        build_version=status.get("build_version"),
        sip_enabled=status.get("sip_enabled"),
        filevault_on=status.get("filevault_on"),
        gatekeeper_on=status.get("gatekeeper_on"),
        firewall_on=status.get("firewall_on"),
        secure_boot=status.get("secure_boot"),
        hardware_model=status.get("hardware_model"),
        serial_number=status.get("serial_number"),
        uptime_secs=status.get("uptime_secs"),
        raw_json=json.dumps(status),
    )
    db.add(snapshot)
    db.commit()

    return status


@router.get("/api/device/connections")
async def get_device_connections(
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    data = await collect_connections()
    whitelist = db.query(UsbWhitelist).all()
    def _is_whitelisted(pid: str, serial: str, volume_uuid: str = "") -> bool:
        for e in whitelist:
            checks = []
            if e.product_id:
                checks.append(pid == e.product_id)
            if e.serial:
                checks.append(serial == e.serial)
            if e.volume_uuid:
                checks.append(volume_uuid == e.volume_uuid)
            if checks and all(checks):
                return True
        return False

    for dev in data.get("usb_devices", []):
        dev["whitelisted"] = _is_whitelisted(
            dev.get("product_id", ""), dev.get("serial", "")
        )
    for vol in data.get("usb_volumes", []):
        vol["whitelisted"] = _is_whitelisted(
            vol.get("parent_product_id", ""), vol.get("parent_serial", ""),
            vol.get("volume_uuid", "")
        )
    return data


@router.get("/api/device/usb-whitelist")
def list_usb_whitelist(
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    entries = db.query(UsbWhitelist).order_by(UsbWhitelist.added_at.desc()).all()
    return [
        {
            "id": e.id,
            "name": e.name,
            "vendor": e.vendor,
            "product_id": e.product_id,
            "serial": e.serial,
            "volume_uuid": e.volume_uuid,
            "notes": e.notes,
            "added_by": e.added_by,
            "added_at": e.added_at.isoformat(),
        }
        for e in entries
    ]


@router.post("/api/device/usb-whitelist", status_code=201)
def add_usb_whitelist(
    body: UsbWhitelistCreate,
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    entry = UsbWhitelist(
        name=body.name,
        vendor=body.vendor,
        product_id=body.product_id,
        serial=body.serial,
        volume_uuid=body.volume_uuid,
        notes=body.notes,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    audit.log_action(db, USB_WHITELIST_ADDED, entry.name, {
        "vendor": entry.vendor,
        "product_id": entry.product_id,
        "serial": entry.serial,
        "volume_uuid": entry.volume_uuid,
    })
    return {
        "id": entry.id,
        "name": entry.name,
        "vendor": entry.vendor,
        "product_id": entry.product_id,
        "serial": entry.serial,
        "notes": entry.notes,
        "added_by": entry.added_by,
        "added_at": entry.added_at.isoformat(),
    }


@router.delete("/api/device/usb-whitelist/{entry_id}", status_code=200)
def remove_usb_whitelist(
    entry_id: int,
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    entry = db.query(UsbWhitelist).filter(UsbWhitelist.id == entry_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Whitelist entry not found")
    name = entry.name
    db.delete(entry)
    db.commit()
    audit.log_action(db, USB_WHITELIST_REMOVED, name, {"id": entry_id})
    return {"deleted": entry_id}


@router.get("/api/preflight")
async def preflight_check(
    db: Session = Depends(get_db),
    _: str = Depends(verify_token),
):
    """
    Pre-flight signing readiness check.
    Checks rules in ALL three standards (74 "universal" rules) + key device status.
    Returns GREEN / YELLOW / RED.
    """
    from core.manifest import get_all_rules
    from core.models import ScanResult

    # Rules in all 3 standards are the critical baseline
    all_rules = get_all_rules()
    universal_rules = [
        r["rule"] for r in all_rules
        if r.get("standards", {}).get("800-53r5_high")
        and r.get("standards", {}).get("cisv8")
        and r.get("standards", {}).get("cis_lvl2")
    ]

    failing = []
    for rule_name in universal_rules:
        latest = (
            db.query(ScanResult)
            .filter(ScanResult.rule == rule_name)
            .order_by(ScanResult.scanned_at.desc())
            .first()
        )
        if latest and latest.status == "FAIL":
            failing.append(rule_name)

    device = await collect_device_status()
    device_issues = []
    if not device.get("sip_enabled"):
        device_issues.append("SIP is disabled")
    if not device.get("filevault_on"):
        device_issues.append("FileVault is off")
    if not device.get("gatekeeper_on"):
        device_issues.append("Gatekeeper is disabled")

    connections = await collect_connections()
    if connections.get("internet_detected"):
        device_issues.append("Active internet connections detected")

    total_issues = len(failing) + len(device_issues)
    if total_issues == 0:
        readiness = "GREEN"
    elif total_issues <= 3:
        readiness = "YELLOW"
    else:
        readiness = "RED"

    audit.log_action(db, audit.PREFLIGHT_RUN, None, {
        "readiness": readiness,
        "failing_universal_rules": len(failing),
        "device_issues": device_issues,
    })

    return {
        "readiness": readiness,
        "universal_rules_checked": len(universal_rules),
        "failing_universal_rules": failing,
        "device_issues": device_issues,
        "device_status": device,
        "checked_at": datetime.utcnow().isoformat(),
    }
