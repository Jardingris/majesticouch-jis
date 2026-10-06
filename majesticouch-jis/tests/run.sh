#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ ! -f "$project/src/majesticouch-jis.c" ]; then
    echo 'FAIL: event-driven helper has not been implemented' >&2
    exit 1
fi
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
/usr/bin/clang -std=c11 -Wall -Wextra -Wpedantic -Werror -O2 \
    "$project/tests/test-helper.c" -framework IOKit -framework CoreFoundation \
    -o "$temporary/test-helper"
"$temporary/test-helper"
binary='/Users/Test & Name/Library/Application Support/MajestouchJIS/majesticouch-jis'
log='/Users/Test & Name/Library/Logs/MajestouchJIS.log'
# Exercise the installer's real plist generation, without loading an Agent.
awk '
    /^cat >.*agent.plist/ { printing=1 }
    printing { print }
    printing && /plutil -lint/ { exit }
' "$project/install.sh" > "$temporary/generate-plist.sh"
. "$temporary/generate-plist.sh"
if [ "$(/usr/bin/plutil -extract ProgramArguments raw -expect array -o - "$temporary/agent.plist")" != 1 ]; then
    echo 'FAIL: LaunchAgent must have exactly one program argument' >&2
    exit 1
fi
[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$temporary/agent.plist")" = "$binary" ]
[ "$(/usr/bin/plutil -extract StandardErrorPath raw -o - "$temporary/agent.plist")" = "$log" ]
if /usr/bin/plutil -extract StartInterval raw -o - "$temporary/agent.plist" >/dev/null 2>&1; then
    echo 'FAIL: polling interval present' >&2; exit 1
fi
echo 'PASS: single executable argument, escaped paths, no polling interval'
