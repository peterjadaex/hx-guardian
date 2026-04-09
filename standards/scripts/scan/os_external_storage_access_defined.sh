#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_external_storage_access_defined
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Access to External Storage Must Be Defined
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_external_storage_access_defined","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/bin/plutil -convert json /var/db/ManagedConfigurationFiles/DiskManagement/DiskManagement_Settings.plist -o - | /usr/bin/jq --raw-output '.Restrictions.ExternalStorage'
)
expected_value="Allowed"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"os_external_storage_access_defined","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"os_external_storage_access_defined","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
