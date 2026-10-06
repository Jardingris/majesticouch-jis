#!/bin/sh
set -eu
umask 077

project=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
label=local.majesticouch.jis-mac
domain="gui/$(id -u)"
appdir="$HOME/Library/Application Support/MajestouchJIS"
binary="$appdir/majesticouch-jis"
plist="$HOME/Library/LaunchAgents/$label.plist"
log="$HOME/Library/Logs/MajestouchJIS.log"
matching='{"Product":"Majestouch Convertible3"}'
temporary=''
backup=''
transaction=0

cleanup()
{
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$result" -ne 0 ] && [ "$transaction" -eq 1 ]; then
        echo "Install failed; restoring $backup" >&2
        sh "$project/uninstall.sh" --restore "$backup" || \
            echo "Automatic restore failed. Run: sh '$project/uninstall.sh' --restore '$backup'" >&2
    fi
    if [ -n "$temporary" ]; then rm -rf "$temporary"; fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

if [ "$(id -u)" -eq 0 ]; then echo 'Run as the logged-in user, without sudo.' >&2; exit 1; fi
if [ "$#" -ne 0 ]; then echo 'Usage: sh install.sh' >&2; exit 1; fi
/usr/bin/xcrun --find clang >/dev/null
/usr/bin/xcrun --show-sdk-path >/dev/null
temporary=$(mktemp -d)
/usr/bin/clang -std=c11 -Wall -Wextra -Wpedantic -Werror -O2 \
    "$project/src/majesticouch-jis.c" -framework IOKit -framework CoreFoundation \
    -o "$temporary/majesticouch-jis"

cat > "$temporary/agent.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.majesticouch.jis-mac</string>
  <key>ProgramArguments</key><array/>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>PLACEHOLDER</string>
</dict></plist>
PLIST
/usr/bin/plutil -insert ProgramArguments.0 -string "$binary" "$temporary/agent.plist"
/usr/bin/plutil -replace StandardErrorPath -string "$log" "$temporary/agent.plist"
/usr/bin/plutil -lint "$temporary/agent.plist"
[ "$(/usr/bin/plutil -extract ProgramArguments raw -expect array -o - "$temporary/agent.plist")" = 1 ]
if [ -e "$plist" ]; then
    existing_label=$(/usr/bin/plutil -extract Label raw -o - "$plist")
    if [ "$existing_label" != "$label" ]; then
        echo 'Existing plist has a different label; refusing replacement.' >&2; exit 1
    fi
fi

mkdir -p "$appdir/backups" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
backup=$(mktemp -d "$appdir/backups/install.$(date +%Y%m%d-%H%M%S).XXXXXX")
if [ -e "$plist" ]; then cp -p "$plist" "$backup/agent.plist"; fi
if [ -e "$binary" ]; then cp -p "$binary" "$backup/majesticouch-jis"; fi
if /bin/launchctl print "$domain/$label" > "$backup/launchd-before.txt" 2>&1; then
    : > "$backup/was-loaded"
fi
/usr/bin/hidutil property --matching "$matching" --get UserKeyMapping > "$backup/mapping-before.txt"
echo "Backup: $backup"

transaction=1
if [ -e "$backup/was-loaded" ]; then /bin/launchctl bootout "$domain/$label"; fi
/usr/bin/install -m 755 "$temporary/majesticouch-jis" "$appdir/.majesticouch-jis.new"
mv -f "$appdir/.majesticouch-jis.new" "$binary"
/usr/bin/install -m 644 "$temporary/agent.plist" "$plist.new"
mv -f "$plist.new" "$plist"
/bin/launchctl bootstrap "$domain" "$plist"
# KeepAlive starts it at bootstrap; do not use kickstart -k (that would apply twice).
/bin/launchctl kickstart "$domain/$label"
# One bounded installation check, not a runtime timer or a polling loop.
/bin/sleep 1
/bin/launchctl print "$domain/$label" > "$temporary/launchd.txt"
if ! /usr/bin/grep -q 'state = running' "$temporary/launchd.txt"; then
    echo 'Helper did not remain running.' >&2; exit 1
fi
pid=$(awk '/^[[:space:]]*pid = / { print $3; exit }' "$temporary/launchd.txt")
[ -n "$pid" ]
/bin/ps -p "$pid" -o pid,ppid,state,%cpu,time,command
/usr/bin/hidutil list --matching "$matching" > "$temporary/devices.txt"
cat "$temporary/devices.txt"
/usr/bin/hidutil property --matching "$matching" --get UserKeyMapping > "$temporary/mapping.txt"
cat "$temporary/mapping.txt"
if /usr/bin/grep -q 'Majestouch Convertible3' "$temporary/devices.txt"; then
    if ! awk '
        function check_service() {
            if (service && (first != 1 || second != 1 || count != 2)) bad=1
        }
        /^[[:xdigit:]]+[[:space:]]+UserKeyMapping/ {
            check_service(); service=1; first=0; second=0; count=0; dst=""
        }
        /HIDKeyboardModifierMappingDst/ { dst=$3; sub(/;/,"",dst) }
        /HIDKeyboardModifierMappingSrc/ {
            src=$3; sub(/;/,"",src)
            if (src == "30064771211" && dst == "30064771217") first++
            if (src == "30064771210" && dst == "30064771216") second++
            count++
        }
        END { check_service(); exit !(service && !bad) }
    ' "$temporary/mapping.txt"; then
        echo 'Connected Majestouch mapping verification failed.' >&2; exit 1
    fi
else
    echo 'Majestouch is disconnected; mapping check deferred until connection.'
fi
transaction=0
echo "Installed: $binary"
echo "Log: $log"
echo "Restore: sh '$project/uninstall.sh' --restore '$backup'"
