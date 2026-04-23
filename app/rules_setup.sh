#!/bin/zsh --no-rcs
# =============================================================================
# rules_setup.sh — Post-install hardening: bulk fixes + exemptions
#
# Run this script after a fresh airgap install to apply all compliance fixes
# and lock in policy exemptions in one shot. Everything is recorded in the app
# database and reflected in the dashboard immediately.
#
# Does not require root — talks to the local HTTP API on 127.0.0.1:8000.
#
# ─────────────────────────────────────────────────────────────────────────────
# AIRGAP DEPLOYMENT GUIDE
# ─────────────────────────────────────────────────────────────────────────────
#
# STEP 1 — Build binaries  (internet-connected Mac)
# ─────────────────────────────────────────────────
#   cd /path/to/hx-guardian
#   zsh app/build.sh
#
#   Output: app/dist/hxg-server   hxg-runner   hxg-usb-watcher
#   (Skip this step if you already have a built transfer/ package.)
#
#
# STEP 2 — Bundle and write to SD card  (internet-connected Mac)
# ──────────────────────────────────────────────────────────────
#   zsh app/prepare_sd_card.sh
#   cp -R transfer/ /Volumes/<SD_CARD>/hxg-install
#
#   What gets bundled into transfer/:
#     app/dist/           pre-built binaries (hxg-server, hxg-runner, hxg-usb-watcher)
#     app/install.sh      main installer
#     app/start.sh        start all services
#     app/stop.sh         stop all services
#     app/restart.sh      restart all services
#     app/update.sh       updater
#     app/rules_setup.sh  this script
#     app/launchd/        LaunchDaemon plists
#     standards/scripts/  scan + fix shell scripts and manifest.json
#     standards/*/mobileconfigs/unsigned/   MDM profiles per standard
#     standards/unified/  merged unified MDM profile
#
#
# STEP 3 — Install on the airgap device
# ──────────────────────────────────────
#   (Insert SD card, open Terminal on the airgap Mac)
#
#   a) Copy install package from the SD card:
#        cp -R /Volumes/<SD_CARD>/hxg-install ~/hxg-install
#
#   b) Run the installer (deploys binaries, standards, LaunchDaemons,
#      password policy, and starts all services automatically):
#        sudo zsh ~/hxg-install/app/install.sh
#
#   c) Install the unified MDM profile:
#        open ~/hxg-install/standards/unified/com.hxguardian.unified.mobileconfig
#        → System Settings → Privacy & Security → Profiles → Install
#      (User approval prompt will appear — click Install)
#
#   d) Optionally remove the install package after install completes:
#        rm -rf ~/hxg-install
#
#
# STEP 4 — Run this script  (post-install hardening)
# ────────────────────────────────────────────────────
#   The server starts automatically at the end of install.sh. Wait ~10 seconds,
#   then run:
#
#     zsh ~/hxg-install/app/rules_setup.sh
#
#   If you removed ~/hxg-install in step 3d, the script is also available at:
#     /Library/Application\ Support/hxguardian/app/rules_setup.sh
#
#   What this script does:
#     Phase 1  Apply fix scripts for all fixable rules
#              (exempt rules below are skipped to avoid disruptive fixes)
#     Phase 2  Create permanent policy exemptions for the listed rules
#     Phase 3  Trigger a full compliance rescan and wait for results
#
#   If 2FA is enabled you will be prompted once for your 6-digit TOTP code.
#   The script automatically re-prompts before the 10-minute session expires.
#
#
# STEP 5 — Verify
# ────────────────
#   Open the dashboard:    http://127.0.0.1:8000
#   Check server log:      tail -f /Library/Logs/hxguardian-server-error.log
#   Check runner log:      tail -f /Library/Logs/hxguardian-runner.log
#   Check service status:  sudo launchctl list | grep hxguardian
#
#
# TROUBLESHOOTING
# ───────────────
#   Server not responding after install:
#     sudo zsh app/start.sh
#
#   Re-running this script is safe — exemptions are idempotent (the API
#   updates existing records rather than creating duplicates).
#
#   A specific fix failed — run it manually:
#     curl -sf -X POST http://127.0.0.1:8000/api/rules/<rule_name>/fix \
#          -H "Content-Type: application/json" \
#          -H "X-2FA-Token: <token>" -d '{}'
#
#   Get a fresh 2FA session token:
#     curl -sf -X POST http://127.0.0.1:8000/api/settings/2fa/verify \
#          -H "Content-Type: application/json" \
#          -d '{"otp":"<6-digit-code>"}'
#
# =============================================================================

readonly API="http://127.0.0.1:8000/api"
readonly SCRIPT_DIR="${0:A:h}"

# =============================================================================
# EXEMPTIONS
# Format: "rule_name|Human-readable reason|expires_at"
#   expires_at: ISO date  YYYY-MM-DD  or  permanent
# =============================================================================
EXEMPT_ENTRIES=(
    # ── Smartcard (hardware not deployed) ────────────────────────────────────
    "auth_pam_login_smartcard_enforce|Hardware smartcard reader not deployed in this environment|permanent"
    "auth_pam_su_smartcard_enforce|Hardware smartcard reader not deployed in this environment|permanent"
    "auth_pam_sudo_smartcard_enforce|Hardware smartcard reader not deployed in this environment|permanent"
    "auth_smartcard_allow|Hardware smartcard reader not deployed in this environment|permanent"
    "auth_smartcard_certificate_trust_enforce_high|Hardware smartcard reader not deployed in this environment|permanent"
    "auth_smartcard_enforce|Hardware smartcard reader not deployed in this environment|permanent"
    "supplemental_smartcard|Hardware smartcard reader not deployed in this environment|permanent"

    # ── Touch ID ─────────────────────────────────────────────────────────────
    "os_touchid_prompt_disable|Touch ID configuration not enforced in this environment|permanent"
    "system_settings_touch_id_settings_disable|Touch ID configuration not enforced in this environment|permanent"
    "system_settings_touchid_unlock_disable|Touch ID configuration not enforced in this environment|permanent"

    # ── Specific policy exceptions ────────────────────────────────────────────
    "os_config_data_install_enforce|Configuration data auto-install disabled per local policy|permanent"
    "os_config_profile_ui_install_disable|Profile UI install not restricted per local policy|permanent"
    "os_httpd_disable|Apache HTTP server managed separately per local policy|permanent"
    "os_root_disable|Root account required for administrative operations in this environment|permanent"

    # ── Software updates (managed via centralized deployment) ─────────────────
    "os_software_update_app_update_enforce|App Store updates managed via centralized deployment|permanent"
    "os_software_update_deferral|Software update deferral managed via centralized policy|permanent"
    "system_settings_download_software_update_enforce|Software downloads managed via centralized deployment|permanent"
    "system_settings_software_update_download_enforce|Software downloads managed via centralized deployment|permanent"
    "system_settings_softwareupdate_current|Software updates managed via centralized deployment|permanent"

    # ── Time Machine ──────────────────────────────────────────────────────────
    "system_settings_time_machine_auto_backup_enable|Time Machine auto-backup disabled per local policy|permanent"

    # ── MDM/DDM-only scans (not satisfiable by user-approved profile) ─────────
    "os_external_storage_access_defined|External storage restrictions require MDM-delivered DiskManagement DDM declaration|permanent"
    "os_mdm_require|Device is intentionally unenrolled from MDM per airgap deployment model|permanent"
    "os_recover_lock_enable|Apple Silicon Recovery Lock requires interactive SecureToken admin signing; run manually via fdesetup if desired|permanent"
    "os_recovery_lock_enable|MDM-issued Recovery Lock unavailable; covered manually via fdesetup|permanent"
    "system_settings_security_update_install|Automatic security-update install state requires DDM declaration (MDM-only)|permanent"
    "system_settings_find_my_disable|Requires com.apple.icloud.managed domain which is MDM-only|permanent"
    "system_settings_token_removal_enforce|Smartcard hardware not deployed in this environment|permanent"

    # ── SSH service disabled entirely (see system_settings_ssh_disable) ──────
    "os_ssh_server_alive_interval_configure|SSH service disabled; ServerAliveInterval not applicable|permanent"

    # ── Password policy attributes that brick local auth on Tahoe if enforced ─
    # Alphanumeric + special-character enforcement is applied via the unified
    # mobileconfig; the rules below are intentionally left un-enforced because
    # applying them via pwpolicy locks users out.
    "pwpolicy_account_inactivity_enforce|Disables accounts after idle days; not enforced to avoid lockout on airgap Macs with infrequent login|permanent"
    "pwpolicy_account_lockout_timeout_enforce|Lockout auto-recovery timer requires MDM-delivered pwpolicy; not enforced locally to avoid login trap|permanent"
    "pwpolicy_custom_regex_enforce|Site-specific regex not defined; enforcing breaks existing passwords|permanent"
    "pwpolicy_history_enforce|Password history breaks local auth when pwpolicy rewrites accountPolicy on Tahoe|permanent"
    "pwpolicy_max_lifetime_enforce|Forced password expiry locks users out on airgap devices with infrequent login|permanent"
    "pwpolicy_minimum_lifetime_enforce|Minimum-lifetime enforcement blocks password rotation during install; bricks local auth on Tahoe|permanent"
    "pwpolicy_simple_sequence_disable|Simple-sequence check invalidates existing passwords; not enforced to avoid lockout|permanent"
)

# =============================================================================
# FIX-ONLY SKIPS
# Rules whose fix_script is known to brick local auth on macOS Tahoe by
# re-applying password-policy primitives that the installer deliberately omits
# (minimumLifetime, inactiveDays, forced reset, etc.). These rules are NOT
# exempted — they will continue to appear as non-compliant in the dashboard
# until the operator addresses them via an MDM profile. Phase 1 simply refuses
# to run their fix_script.
# =============================================================================
SKIP_FIX_ENTRIES=(
    "pwpolicy_minimum_lifetime_enforce"
    "pwpolicy_account_inactivity_enforce"
)

# =============================================================================
# INTERNALS — do not edit below this line
# =============================================================================

# Build fast-lookup map of exempt rule names
typeset -A _EXEMPT_MAP
for _e in "${EXEMPT_ENTRIES[@]}"; do
    _EXEMPT_MAP[${_e%%|*}]=1
done
unset _e

# Build fast-lookup map of fix-only skipped rule names
typeset -A _SKIP_FIX_MAP
for _s in "${SKIP_FIX_ENTRIES[@]}"; do
    _SKIP_FIX_MAP[$_s]=1
done
unset _s

SESSION_TOKEN=""
SESSION_START=0
readonly SESSION_TTL=540  # re-auth at 9 min; server TTL is 10 min

# ── Helpers ───────────────────────────────────────────────────────────────────

# Read one field from a JSON object on stdin
_jget() { python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null; }

_log()  { print "  $*"; }
_ok()   { printf "  \033[32mOK\033[0m    %s\n" "$*"; }
_fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$*"; }
_na()   { printf "  \033[33mN/A\033[0m   %s\n" "$*"; }

# ── 2FA ───────────────────────────────────────────────────────────────────────

_2fa_enabled() {
    local resp
    resp=$(curl -sf "$API/settings/2fa/status" 2>/dev/null) || return 1
    [[ $(print "$resp" | _jget "is_enabled") == "True" ]]
}

_authenticate() {
    if ! _2fa_enabled; then
        SESSION_TOKEN="disabled"
        SESSION_START=$(date +%s)
        _log "2FA is not configured — no token needed."
        return 0
    fi

    print -n "  Enter 6-digit TOTP code: "
    read -r _otp

    local resp
    resp=$(curl -sf -X POST "$API/settings/2fa/verify" \
        -H "Content-Type: application/json" \
        -d "{\"otp\":\"$_otp\"}" 2>/dev/null) || {
        print "  Cannot reach 2FA endpoint." >&2
        return 1
    }

    [[ $(print "$resp" | _jget "valid") != "True" ]] && {
        print "  Invalid OTP code." >&2
        return 1
    }

    SESSION_TOKEN=$(print "$resp" | _jget "session_token")
    SESSION_START=$(date +%s)
    _log "Authenticated (session valid for 10 min)."
}

# Re-authenticate before the server-side TTL expires
_ensure_token() {
    (( $(date +%s) - SESSION_START >= SESSION_TTL )) || return 0
    print ""
    print "  [2FA session expiring — please re-enter your TOTP code]"
    _authenticate
}

# POST with 2FA token
_post() {
    _ensure_token || return 1
    curl -sf -X POST "$API$1" \
        -H "Content-Type: application/json" \
        -H "X-2FA-Token: $SESSION_TOKEN" \
        -d "$2" 2>/dev/null
}

# ── Server readiness ──────────────────────────────────────────────────────────

_wait_for_server() {
    print "  Waiting for HX-Guardian server at $API..."
    local i=0
    while (( i < 30 )); do
        curl -sf "$API/rules/meta" >/dev/null 2>&1 && {
            _log "Server is ready."
            return 0
        }
        (( i++ ))
        sleep 2
    done
    print "  Server did not respond after 60 seconds." >&2
    print "  Start it with:  sudo zsh app/start.sh" >&2
    return 1
}

# ── Manifest path ─────────────────────────────────────────────────────────────

_manifest_path() {
    local frozen="/Library/Application Support/hxguardian/standards/scripts/manifest.json"
    local dev="$SCRIPT_DIR/../standards/scripts/manifest.json"
    if   [[ -f "$frozen" ]]; then print "$frozen"
    elif [[ -f "$dev"    ]]; then print "$dev"
    else
        print "Cannot find manifest.json" >&2
        return 1
    fi
}

# ── Phase 1: Fixes ────────────────────────────────────────────────────────────

_run_fixes() {
    local manifest
    manifest=$(_manifest_path) || return 1

    # All fixable rules from manifest
    local all_fixable
    all_fixable=$(python3 - "$manifest" <<'PYEOF'
import sys, json
with open(sys.argv[1]) as f:
    m = json.load(f)
for rule in sorted(m):
    if m[rule].get("fix_script"):
        print(rule)
PYEOF
)

    # Exclude exempt rules and fix-only skips
    local rules_to_fix=()
    local skipped_fix=()
    while IFS= read -r rule; do
        [[ -n "${_EXEMPT_MAP[$rule]}" ]] && continue
        if [[ -n "${_SKIP_FIX_MAP[$rule]}" ]]; then
            skipped_fix+=("$rule")
            continue
        fi
        rules_to_fix+=("$rule")
    done <<< "$all_fixable"

    local total=${#rules_to_fix[@]}
    local ok=0 fail=0 na=0 n=0

    print ""
    print "── Phase 1: Fixes ($total rules, skipping ${#EXEMPT_ENTRIES[@]} exempt, ${#skipped_fix[@]} fix-only skipped) ──────"
    print ""

    for rule in "${skipped_fix[@]}"; do
        _na "$rule  (fix skipped — known to break local auth on Tahoe)"
    done
    (( ${#skipped_fix[@]} > 0 )) && print ""

    for rule in "${rules_to_fix[@]}"; do
        (( n++ ))
        local resp
        resp=$(_post "/rules/$rule/fix" "{}") || {
            printf "  [%3d/%d] " "$n" "$total"; _fail "$rule (request error)"
            (( fail++ ))
            continue
        }

        local action scan_result
        action=$(print "$resp" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); print(d.get('fix',{}).get('action','?'))" 2>/dev/null)
        scan_result=$(print "$resp" | _jget "scan_result")

        case "$action" in
            EXECUTED)
                printf "  [%3d/%d] " "$n" "$total"; _ok "$rule  (scan → $scan_result)"
                (( ok++ )) ;;
            NOT_APPLICABLE)
                printf "  [%3d/%d] " "$n" "$total"; _na "$rule"
                (( na++ )) ;;
            *)
                printf "  [%3d/%d] " "$n" "$total"; _fail "$rule  (action=$action)"
                (( fail++ )) ;;
        esac
    done

    print ""
    print "  Fixes complete: $ok executed, $na not-applicable, $fail failed  (total $total)"
}

# ── Phase 2: Exemptions ───────────────────────────────────────────────────────

_create_exemptions() {
    local total=${#EXEMPT_ENTRIES[@]}
    local ok=0 fail=0 n=0

    print ""
    print "── Phase 2: Exemptions ($total rules) ──────────────────────────────────────"
    print ""

    for entry in "${EXEMPT_ENTRIES[@]}"; do
        (( n++ ))
        local rule="${entry%%|*}"
        local rest="${entry#*|}"
        local reason="${rest%%|*}"
        local expires="${rest#*|}"

        # Build JSON body safely (handles special chars in reason)
        local body
        body=$(python3 - "$rule" "$reason" "$expires" <<'PYEOF'
import sys, json
rule, reason, expires = sys.argv[1], sys.argv[2], sys.argv[3]
d = {
    "rule": rule,
    "reason": reason,
    "expires_at": None if expires == "permanent" else expires + "T00:00:00"
}
print(json.dumps(d))
PYEOF
)

        local resp
        resp=$(_post "/exemptions" "$body") || {
            printf "  [%3d/%d] " "$n" "$total"; _fail "$rule (request error)"
            (( fail++ ))
            continue
        }

        local exp_display
        [[ "$expires" == "permanent" ]] && exp_display="permanent" || exp_display="expires $expires"
        printf "  [%3d/%d] " "$n" "$total"; _ok "$rule  ($exp_display)"
        (( ok++ ))
    done

    print ""
    print "  Exemptions complete: $ok created, $fail failed  (total $total)"
}

# ── Phase 3: Rescan ───────────────────────────────────────────────────────────

_run_rescan() {
    print ""
    print "── Phase 3: Rescan ──────────────────────────────────────────────────────────"
    print ""

    local resp
    resp=$(curl -sf -X POST "$API/scans" \
        -H "Content-Type: application/json" \
        -d '{}' 2>/dev/null)

    local session_id
    session_id=$(print "$resp" | _jget "session_id")

    if [[ -z "$session_id" ]]; then
        _fail "Could not start rescan — use the app to trigger one manually."
        return
    fi

    _log "Rescan started  (session: $session_id)"
    _log "Polling for completion..."

    local i=0
    while (( i < 60 )); do
        sleep 5
        local status_json
        status_json=$(curl -sf "$API/scans/$session_id" 2>/dev/null)
        local is_running
        is_running=$(print "$status_json" | _jget "is_running")

        if [[ "$is_running" == "False" ]]; then
            local score pass_c fail_c exempt_c na_c
            score=$(print "$status_json" | python3 -c \
                "import sys,json; d=json.load(sys.stdin); print(round(d.get('score_pct',0),1))" 2>/dev/null)
            pass_c=$(print "$status_json"    | _jget "pass_count")
            fail_c=$(print "$status_json"    | _jget "fail_count")
            exempt_c=$(print "$status_json"  | _jget "exempt_count")
            na_c=$(print "$status_json"      | _jget "na_count")
            print ""
            _ok "Rescan complete"
            print "       Score:   ${score}%"
            print "       Pass:    $pass_c  |  Fail: $fail_c  |  Exempt: $exempt_c  |  N/A: $na_c"
            return
        fi
        (( i++ ))
    done

    _log "Rescan still running — check the app dashboard for live progress."
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    print ""
    print "════════════════════════════════════════════════════"
    print "  HX-Guardian  ·  Rules Setup"
    print "════════════════════════════════════════════════════"
    print ""

    _wait_for_server || exit 1
    print ""
    _authenticate    || exit 1

    _run_fixes
    _create_exemptions
    _run_rescan

    print ""
    print "════════════════════════════════════════════════════"
    print "  All done.  Reload the app to confirm the changes."
    print "════════════════════════════════════════════════════"
    print ""
}

main "$@"
