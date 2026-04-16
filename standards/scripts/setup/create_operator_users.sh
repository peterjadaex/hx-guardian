#!/bin/zsh
# create_operator_users.sh
# Creates 5 local operator accounts for an airgapped macOS device.
#
# Requirements:
#   - Run as root: sudo zsh create_operator_users.sh
#   - macOS 12 Monterey or later (sysadminctl -addUser API)
#   - Touch ID is intentionally left enabled for all created users
#
# Output:
#   Prints a summary table of usernames and temporary passwords.
#   Each user must change their password on next login.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
OPERATORS=(operator01 operator02 operator03 operator04 operator05)
REAL_NAMES=("Operator 01" "Operator 02" "Operator 03" "Operator 04" "Operator 05")
START_UID=511   # UIDs 511-515; well above macOS reserved range

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  print "ERROR: This script must be run as root (sudo zsh $0)" >&2
  exit 1
fi

if [[ $OSTYPE != darwin* ]]; then
  print "ERROR: macOS only." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Generate a random 16-character alphanumeric password (no ambiguous chars)
gen_password() {
  LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' < /dev/urandom | head -c 16
}

# Return next UID at or above $1 that is not already in use
next_available_uid() {
  local uid=$1
  while dscl . -list /Users UniqueID | awk '{print $2}' | grep -qx "$uid" 2>/dev/null; do
    (( uid++ ))
  done
  print $uid
}

user_exists() {
  dscl . -read /Users/$1 &>/dev/null
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

print ""
print "=== Creating Operator Users ==="
print ""

typeset -A results  # username -> temp_password

for i in {1..5}; do
  username=${OPERATORS[$i]}
  fullname=${REAL_NAMES[$i]}
  uid=$(next_available_uid $(( START_UID + i - 1 )))

  if user_exists "$username"; then
    print "  SKIP  $username — already exists"
    results[$username]="(existing account)"
    continue
  fi

  # Generate temp password
  tmppass=$(gen_password)

  # Create the user account
  sysadminctl \
    -addUser "$username" \
    -fullName "$fullname" \
    -UID "$uid" \
    -password "$tmppass" \
    -home "/Users/$username" \
    -shell /bin/zsh \
    2>&1 | sed 's/^/    /'

  if ! user_exists "$username"; then
    print "  ERROR creating $username" >&2
    continue
  fi

  # Ensure home directory exists
  createhomedir -c -u "$username" &>/dev/null || true

  # Force password change on next login
  # pwpolicy applies per-user override on top of global policy
  pwpolicy -u "$username" -setpolicy "newPasswordRequired=1" 2>/dev/null || true

  # Disable admin rights (belt-and-suspenders — sysadminctl doesn't add admin by default)
  dseditgroup -o edit -d "$username" -t user admin 2>/dev/null || true

  results[$username]=$tmppass
  print "  OK    $username (UID $uid)"
done

# ---------------------------------------------------------------------------
# Summary table
# ---------------------------------------------------------------------------
print ""
print "=== Operator Accounts Summary ==="
printf "%-14s  %-18s  %s\n" "Username" "Temp Password" "Note"
printf "%-14s  %-18s  %s\n" "--------" "-------------" "----"
for username in ${OPERATORS[@]}; do
  printf "%-14s  %-18s  %s\n" "$username" "${results[$username]}" "Change required on first login"
done
print ""
print "Touch ID: Each user can enroll fingerprints after first login via"
print "  System Settings > Touch ID & Password"
print ""
print "IMPORTANT: Store these temporary passwords securely and shred this output."
print "           Users must change their password before the device is airgapped."
