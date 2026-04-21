#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      pwpolicy_account_inactivity_enforce
# Source:    800-53r5_high
# Category:  Password Policy
# Standards: cisv8, 800-53r5_high
# Description: Disable Accounts after 35 Days of Inactivity
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"pwpolicy_account_inactivity_enforce","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

PWPOLICY_FILE="$(mktemp /tmp/hxg-pwpolicy.XXXXXX.plist)"
cat > "$PWPOLICY_FILE" << 'PWPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>policyCategoryAuthentication</key>
    <array>
        <dict>
            <key>policyContent</key>
            <string>policyAttributeFailedAuthentications &lt; policyAttributeMaximumFailedAuthentications</string>
            <key>policyIdentifier</key>
            <string>maxFailedAttempts</string>
            <key>policyParameters</key>
            <dict>
                <key>policyAttributeMaximumFailedAuthentications</key>
                <integer>5</integer>
            </dict>
        </dict>
        <dict>
            <key>policyContent</key>
            <string>(policyAttributeCurrentTime - policyAttributeLastFailedAuthenticationTime) &gt; autoEnableInSeconds</string>
            <key>policyIdentifier</key>
            <string>autoEnable</string>
            <key>policyParameters</key>
            <dict>
                <key>autoEnableInSeconds</key>
                <integer>900</integer>
            </dict>
        </dict>
    </array>
    <key>policyCategoryPasswordChange</key>
    <array>
        <dict>
            <key>policyContent</key>
            <string>policyAttributeCurrentTime &gt; policyAttributeLastPasswordChangeTime + policyAttributeMinimumLifetimeHours * 3600</string>
            <key>policyIdentifier</key>
            <string>minimumLifetime</string>
            <key>policyParameters</key>
            <dict>
                <key>policyAttributeMinimumLifetimeHours</key>
                <integer>24</integer>
            </dict>
        </dict>
        <dict>
            <key>policyContent</key>
            <string>policyAttributeCurrentTime &lt; policyAttributeLastPasswordChangeTime + policyAttributeExpiresEveryNDays * 24 * 60 * 60</string>
            <key>policyIdentifier</key>
            <string>maxLifetime</string>
            <key>policyParameters</key>
            <dict>
                <key>policyAttributeExpiresEveryNDays</key>
                <integer>60</integer>
            </dict>
        </dict>
        <dict>
            <key>policyContent</key>
            <string>none of policyAttributePasswordHashes in policyAttributePasswordHistory</string>
            <key>policyIdentifier</key>
            <string>passwordHistory</string>
            <key>policyParameters</key>
            <dict>
                <key>policyAttributePasswordHistoryDepth</key>
                <integer>5</integer>
            </dict>
        </dict>
    </array>
    <key>policyCategoryPasswordContent</key>
    <array>
        <dict>
            <key>policyContent</key>
            <string>policyAttributePassword matches '.{15,}'</string>
            <key>policyIdentifier</key>
            <string>minimumLength</string>
            <key>policyParameters</key>
            <dict>
                <key>policyAttributeMinimumLength</key>
                <integer>15</integer>
            </dict>
        </dict>
        <dict>
            <key>policyContent</key>
            <string>policyAttributePassword matches '.*[a-zA-Z].*' and policyAttributePassword matches '.*[0-9].*'</string>
            <key>policyIdentifier</key>
            <string>requireAlphanumeric</string>
        </dict>
        <dict>
            <key>policyContent</key>
            <string>policyAttributePassword matches '^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9]).*$'</string>
            <key>policyIdentifier</key>
            <string>customRegex</string>
        </dict>
        <dict>
            <key>policyContent</key>
            <string>policyAttributePassword matches '(.*[^a-zA-Z0-9].*){1,}'</string>
            <key>policyIdentifier</key>
            <string>requireSpecialCharacter</string>
        </dict>
        <dict>
            <key>policyContent</key>
            <string>policyAttributePassword matches '^(?!.*(.)\1{2})(?!.*(abcde|bcdef|cdefg|defgh|efghi|fghij|ghijk|hijkl|ijklm|jklmn|klmno|lmnop|mnopq|nopqr|opqrs|pqrst|qrstu|rstuv|stuvw|tuvwx|uvwxy|vwxyz|edcba|dcbaz|01234|12345|23456|34567|45678|56789|43210|54321|65432|76543|87654|98765)).*$'</string>
            <key>policyIdentifier</key>
            <string>allowSimple</string>
        </dict>
    </array>
    <key>policyAttributeInactiveDays</key>
    <integer>35</integer>
</dict>
</plist>
PWPLIST

/usr/bin/pwpolicy -n /Local/Default -setaccountpolicies "$PWPOLICY_FILE"
STATUS=$?
rm -f "$PWPOLICY_FILE"

if [[ $STATUS -eq 0 ]]; then
    printf '{"rule":"pwpolicy_account_inactivity_enforce","action":"EXECUTED","message":"Fix applied"}\n'
    exit 0
else
    printf '{"rule":"pwpolicy_account_inactivity_enforce","action":"FAILED","message":"pwpolicy returned non-zero"}\n'
    exit 1
fi
