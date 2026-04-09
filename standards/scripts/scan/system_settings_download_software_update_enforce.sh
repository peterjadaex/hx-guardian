#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      system_settings_download_software_update_enforce
# Source:    cisv8
# Category:  System Settings
# Standards: cisv8
# Description: Enforce Software Update Downloads Updates Automatically using DDM.
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"system_settings_download_software_update_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

result_value=$(/usr/bin/plutil -convert json /var/db/softwareupdate/SoftwareUpdateDDMStatePersistence.plist -o - | /usr/bin/jq --raw-output .'SUCorePersistedStatePolicyFields.SUCoreDDMDeclarationGlobalSettings.automaticallyDownload'
)
expected_value="1"

if [[ "$result_value" == "$expected_value" ]]; then
    printf '{"rule":"system_settings_download_software_update_enforce","status":"PASS","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 0
else
    printf '{"rule":"system_settings_download_software_update_enforce","status":"FAIL","result":"%s","expected":"%s"}\n' "$result_value" "$expected_value"
    exit 1
fi
