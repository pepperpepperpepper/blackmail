# trollstore-range.sh — whether TrollStore installs on an iPad's iOS, from
# its ProductVersion and BuildVersion. Sourced by provision-ipad.sh, and by
# the host test that pins the rule (ProvisionRangeTests), so the two cannot
# drift apart.
#
# TrollStore's README: "Supported versions: 14.0 beta 2 - 16.6.1, 16.7 RC
# (20H18), 17.0", and "16.7.x (excluding 16.7 RC) and 17.0.1+ will NEVER be
# supported". The 16.7 RC and the 16.7 that shipped share the version
# "16.7"; only the build tells them apart: 20H18 is the RC. 14.0's first
# beta, which TrollStore does not take, is not told apart from 14.0.
#
#   trollstore_range VERSION [BUILD]
#
# prints one word: "in" (TrollStore installs on it, exit 0), "below" (older
# than 14.0), "past" (newer than TrollStore reaches, or 16.7.x), or
# "unknown" (no version read, or not one); exit 1 for all but "in".
trollstore_range() {
    local version="$1" build="${2:-}"
    # One to three parts of digits, a dot between each.
    case "$version" in
        ''|*[!0-9.]*|.*|*.|*..*|*.*.*.*) echo unknown; return 1 ;;
    esac
    local major minor patch
    IFS=. read -r major minor patch <<< "$version"
    # Base 10 throughout: "08" is eight, not a bad octal number.
    local n=$(( 10#$major * 10000 + 10#${minor:-0} * 100 + 10#${patch:-0} ))
    if   [ "$n" -lt 140000 ]; then echo below; return 1
    elif [ "$n" -le 160601 ]; then echo in; return 0
    elif [ "$n" -eq 160700 ] && [ "$build" = 20H18 ]; then echo in; return 0
    elif [ "$n" -eq 170000 ]; then echo in; return 0
    else echo past; return 1
    fi
}
