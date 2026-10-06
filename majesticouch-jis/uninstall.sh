#!/bin/sh
set -eu
umask 077

label=local.majesticouch.jis-mac
domain="gui/$(id -u)"
appdir="$HOME/Library/Application Support/MajestouchJIS"
binary="$appdir/majesticouch-jis"
plist="$HOME/Library/LaunchAgents/$label.plist"
matching='{"Product":"Majestouch Convertible3"}'

if [ "$(id -u)" -eq 0 ]; then echo 'Run as the logged-in user, without sudo.' >&2; exit 1; fi
restore=''
case "$#" in
    0) ;;
    2) if [ "$1" = '--restore' ]; then restore=$2; else exit 1; fi ;;
    *) echo 'Usage: sh uninstall.sh [--restore BACKUP_DIRECTORY]' >&2; exit 1 ;;
esac
if [ -n "$restore" ]; then
    case "$restore" in "$appdir"/backups/*) ;; *) echo 'Use a backup under MajestouchJIS/backups.' >&2; exit 1 ;; esac
    [ -d "$restore" ]
    [ -f "$restore/launchd-before.txt" ]
    if [ -e "$restore/agent.plist" ]; then
        /usr/bin/plutil -lint "$restore/agent.plist"
        [ "$(/usr/bin/plutil -extract Label raw -o - "$restore/agent.plist")" = "$label" ]
    fi
fi
if [ -e "$plist" ]; then
    [ "$(/usr/bin/plutil -extract Label raw -o - "$plist")" = "$label" ]
fi

mkdir -p "$appdir/backups"
backup=$(mktemp -d "$appdir/backups/uninstall.$(date +%Y%m%d-%H%M%S).XXXXXX")
if [ -e "$plist" ]; then cp -p "$plist" "$backup/agent.plist"; fi
if [ -e "$binary" ]; then cp -p "$binary" "$backup/majesticouch-jis"; fi
if ! /usr/bin/hidutil property --matching "$matching" --get UserKeyMapping \
    > "$backup/mapping-before.txt" 2> "$backup/mapping-error.txt"; then
    echo 'Mapping snapshot unavailable; continuing with file/Agent recovery.' >&2
fi
if /bin/launchctl print "$domain/$label" > "$backup/launchd-before.txt" 2>&1; then
    : > "$backup/was-loaded"
    /bin/launchctl bootout "$domain/$label"
fi
# Move only these two known files; keep all backups and logs.
if [ -e "$plist" ]; then mv "$plist" "$backup/removed-agent.plist"; fi
if [ -e "$binary" ]; then mv "$binary" "$backup/removed-majesticouch-jis"; fi

if [ -n "$restore" ]; then
    if [ -e "$restore/majesticouch-jis" ]; then
        /usr/bin/install -m 755 "$restore/majesticouch-jis" "$binary"
    fi
    if [ -e "$restore/agent.plist" ]; then
        /usr/bin/install -m 644 "$restore/agent.plist" "$plist"
    fi
    if [ -e "$restore/was-loaded" ]; then
        /bin/launchctl bootstrap "$domain" "$plist"
        /bin/launchctl print "$domain/$label"
    fi
    echo "Restored: $restore"
else
    /usr/bin/hidutil property --matching "$matching" --set '{"UserKeyMapping":[]}'
    /usr/bin/hidutil property --matching "$matching" --get UserKeyMapping
    echo 'Uninstalled; only the Majestouch mapping was cleared.'
fi
echo "Preserved current files: $backup"
