#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_policy_banner_loginwindow_enforce
# Source:    800-53r5_high
# Category:  Operating System
# Standards: cis_lvl2, 800-53r5_high
# Description: Display Policy Banner at Login Window
# =============================================================================
# Hand-maintained — do not overwrite with generate_scripts.py output.
# Banner text is the HydraX Pte. Ltd. notice, not the mSCP U.S. Government default.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_policy_banner_loginwindow_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

bannerText="You are accessing an information system owned and operated by [HydraX Pte. Ltd.], including all connected devices and storage media. This system is for authorized personnel and authorized use only. All activities on the system are monitored, recorded and audited. Unauthorized access, use or modification is prohibited and may constitute an offence under applicable laws, and may result in disciplinary and/or legal action. By proceeding, you acknowledge this notice and consent to such monitoring."
/bin/mkdir -p /Library/Security/PolicyBanner.rtfd
/usr/bin/textutil -convert rtf -output /Library/Security/PolicyBanner.rtfd/TXT.rtf -stdin <<EOF
$bannerText
EOF

printf '{"rule":"os_policy_banner_loginwindow_enforce","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
