#!/usr/bin/env bash
# Fails if any Theme constant is never read.
#
# Theme.swift opens by claiming it holds "every layout number in the app".
# That claim was false: seven constants had zero call sites, and four of the
# layout faults found in the first measurement pass existed *because* a number
# was declared here and then never consulted — the file described a build that
# did not exist. Phase 10 freezes this file, and freezing numbers nothing reads
# would freeze a fiction.
#
# A constant counts as read if it is used anywhere outside Theme.swift, OR
# inside Theme.swift somewhere other than its own declaration (row heights feed
# the scaled variants, baselines feed each other's pitch, and so on).
set -uo pipefail
cd "$(dirname "$0")"

THEME=Sources/Blackmail/Theme/Theme.swift
dead=0

for name in $(grep -oE 'static (let|var) [a-zA-Z_][a-zA-Z0-9_]*' "$THEME" | awk '{print $3}'); do
    # Uses elsewhere in the app.
    outside=$(grep -rhoF --include='*.swift' "Theme.$name" Sources/ \
              | grep -c . || true)
    # Uses inside Theme.swift that are not the declaration itself.
    inside=$(grep -nE "(^|[^.[:alnum:]_])${name}([^[:alnum:]_(]|$)" "$THEME" \
             | grep -vE "static (let|var) ${name}\b" | grep -c . || true)

    if [ "$outside" -eq 0 ] && [ "$inside" -eq 0 ]; then
        echo "DEAD: Theme.$name is declared and never read"
        dead=$((dead + 1))
    fi
done

if [ "$dead" -gt 0 ]; then
    echo
    echo "$dead dead constant(s). Either wire it up or delete it — do not leave"
    echo "Theme.swift asserting a number the build never reads."
    exit 1
fi
echo "All Theme constants have readers."
