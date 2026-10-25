# trollstore-range.sh — whether TrollStore installs on an iPad's iOS, from
# its ProductVersion and BuildVersion, and whether the app does at all.
# Sourced by provision-ipad.sh, and by the host test that pins the rules
# (ProvisionRangeTests), so the two cannot drift apart.
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
#
#   ios_below VERSION MINIMUM
#
# exit 0 when VERSION is read and is older than MINIMUM, the app's
# MinimumOSVersion; exit 1 otherwise, a version not read among them, which
# is not known to be older. Prints nothing.

# A version as one number, 16.6.1 as 160601: one to three parts of digits,
# a dot between each, read in base 10 ("08" is eight, not a bad octal
# number). Prints nothing, exit 1, for anything else.
ios_number() {
    case "$1" in
        ''|*[!0-9.]*|.*|*.|*..*|*.*.*.*) return 1 ;;
    esac
    local major minor patch
    IFS=. read -r major minor patch <<< "$1"
    echo $(( 10#$major * 10000 + 10#${minor:-0} * 100 + 10#${patch:-0} ))
}

ios_below() {
    local n m
    n=$(ios_number "$1") && m=$(ios_number "$2") && [ "$n" -lt "$m" ]
}

trollstore_range() {
    local version="$1" build="${2:-}" n
    n=$(ios_number "$version") || { echo unknown; return 1; }
    if   [ "$n" -lt 140000 ]; then echo below; return 1
    elif [ "$n" -le 160601 ]; then echo in; return 0
    elif [ "$n" -eq 160700 ] && [ "$build" = 20H18 ]; then echo in; return 0
    elif [ "$n" -eq 170000 ]; then echo in; return 0
    else echo past; return 1
    fi
}
