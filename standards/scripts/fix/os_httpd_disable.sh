#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_httpd_disable
# Source:    800-53r5_high
# Category:  Operating System
# Standards: cis_lvl2, cisv8, 800-53r5_high
# Description: Disable the Built-in Web Server
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_httpd_disable","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

/usr/sbin/apachectl stop 2>/dev/null
/bin/launchctl disable system/org.apache.httpd

printf '{"rule":"os_httpd_disable","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
