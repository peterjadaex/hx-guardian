#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_sshd_fips_compliant (UNDO)
# Category:  Operating System
# Description: Remove the FIPS-restricted Ciphers/MACs/KexAlgorithms lines from
#              01-mscp-sshd.conf and unlink /etc/ssh/crypto.conf if the fix set it.
# =============================================================================
# Exit codes: 0=OK  1=ERROR  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_sshd_fips_compliant","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -n $include_dir && -f "${include_dir}01-mscp-sshd.conf" ]]; then
    /usr/bin/sed -i.undo.bak \
        -e '/^Ciphers aes128-gcm@openssh.com$/d' \
        -e '/^HostbasedAcceptedAlgorithms /d' \
        -e '/^HostKeyAlgorithms /d' \
        -e '/^KexAlgorithms ecdh-sha2-nistp256$/d' \
        -e '/^MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-256$/d' \
        -e '/^PubkeyAcceptedAlgorithms /d' \
        -e '/^CASignatureAlgorithms /d' \
        "${include_dir}01-mscp-sshd.conf"
fi

# Remove the fips crypto symlink if present
if [[ -L /etc/ssh/crypto.conf ]] && [[ "$(/usr/bin/readlink /etc/ssh/crypto.conf)" == "/etc/ssh/crypto/fips.conf" ]]; then
    /bin/rm -f /etc/ssh/crypto.conf
fi

printf '{"rule":"os_sshd_fips_compliant","action":"UNDONE","message":"Undo applied"}\n'
exit 0
