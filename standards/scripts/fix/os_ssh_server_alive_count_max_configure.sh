#!/bin/zsh --no-rcs
# =============================================================================
# Rule:      os_ssh_server_alive_count_max_configure
# Source:    800-53r5_high
# Category:  Operating System
# Standards: 800-53r5_high
# Description: Set SSH Active Server Alive Maximum to *ODV*
# =============================================================================
# Auto-generated - do not edit manually.
# Exit codes: 0=PASS/OK  1=FAIL/ERROR  2=NOT_APPLICABLE  3=ERROR(root)

if [[ $EUID -ne 0 ]]; then
    printf '{"rule":"os_ssh_server_alive_count_max_configure","status":"ERROR","message":"Must be run as root"}\n'
    exit 3
fi

arch=$(/usr/bin/arch)
CURRENT_USER=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/ssh_config | /usr/bin/tr -d '*')

ssh_config=("ServerAliveCountMax 0")

ssh_setting=$(echo $ssh_config | /usr/bin/cut -d " " -f1)
/usr/bin/grep -qEi "^$ssh_setting" "${include_dir}01-mscp-ssh.conf" && /usr/bin/sed -i "" "s/^$ssh_setting.*/${ssh_config}/" "${include_dir}01-mscp-ssh.conf" || echo "$ssh_config" >> "${include_dir}01-mscp-ssh.conf"
for u in $(/usr/bin/dscl . list /users shell | /usr/bin/egrep -v '(^_)|(root)|(/usr/bin/false)' | /usr/bin/awk '{print $1}'); do
  config=$(/usr/bin/sudo -u $u /usr/bin/ssh -Gv . 2>&1)
  configfiles=$(echo "$config" | /usr/bin/awk '/Reading configuration data/ {print $NF}'| /usr/bin/tr -d '\r')
  configarray=( ${(f)configfiles} )
  if ! echo $config | /usr/bin/grep -q -i "$ssh_config" ; then
    for c in $configarray; do
      if [[ "$c" == "/etc/ssh/crypto.conf" ]]; then
        continue
      fi
      
      /usr/bin/sudo -u $u /usr/bin/grep -qEi "^$ssh_setting" "$c" && /usr/bin/sed -i "" "s/^$ssh_setting.*/${ssh_config}/I" "$c"
      if [[ "$c" =~ ".ssh/config" ]]; then
        if /usr/bin/grep -qEi "$ssh_setting" "$c" 2> /dev/null; then
          old_file=$(cat ~$u/.ssh/config)
          echo "$ssh_config" > ~$u/.ssh/config
          echo "$old_file" >> ~$u/.ssh/config

printf '{"rule":"os_ssh_server_alive_count_max_configure","action":"EXECUTED","message":"Fix applied"}\n'
exit 0
