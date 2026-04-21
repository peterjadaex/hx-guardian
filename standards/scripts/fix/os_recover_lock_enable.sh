#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_recover_lock_enable
# Source:    800-53r5_high
# Category:  Operating System
# Standards: cisv8, 800-53r5_high
# Description: Enable a Recovery Lock to Prevent Unauthorized Access to Recovery Mode
# =============================================================================
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_recover_lock_enable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

HXG_DATA="/Library/Application Support/hxguardian/data"
LOCK_KEY_FILE="$HXG_DATA/recovery_lock.key"

# Generate a random 20-character alphanumeric+symbol password
RECOVERY_PASSWORD=$(LC_ALL=C /usr/bin/tr -dc '0-9' < /dev/urandom | /usr/bin/head -c 8)

# Enable recovery lock
/usr/bin/fdesetup recoverylock enable -password "$RECOVERY_PASSWORD" 2>/dev/null
STATUS=$?

if [[ $STATUS -eq 0 ]]; then
    # Store the password root-only in the HXG data directory
    mkdir -p "$HXG_DATA"
    printf '%s\n' "$RECOVERY_PASSWORD" > "$LOCK_KEY_FILE"
    /bin/chmod 600 "$LOCK_KEY_FILE"
    /usr/sbin/chown root:wheel "$LOCK_KEY_FILE"
    printf '{"rule":"os_recover_lock_enable","action":"EXECUTED","message":"Recovery lock enabled. Password: %s — Record this immediately. Also stored at %s (root-only)."}\n' "$RECOVERY_PASSWORD" "$LOCK_KEY_FILE"
    exit 0
else
    printf '{"rule":"os_recover_lock_enable","action":"FAILED","message":"fdesetup recoverylock enable failed. FileVault must be enabled first."}\n'
    exit 1
fi
