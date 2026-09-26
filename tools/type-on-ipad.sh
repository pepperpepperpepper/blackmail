#!/usr/bin/env bash
# type-on-ipad.sh — type a string on the iPad's on-screen keyboard.
#
# Exists so a password can go from a secrets file onto the device WITHOUT ever
# being displayed, logged, or passed as a command-line argument. The value is
# read from the environment and turned straight into taps; it is never echoed
# and never appears in `ps`, so it stays out of logs and out of
# shell history.
#
#   source <your secrets file>
#   BLACKMAIL_TEST_PASSWORD="$BLACKMAIL_TEST_PASSWORD" ./type-on-ipad.sh --var BLACKMAIL_TEST_PASSWORD
#
# Key coordinates were measured from a screenshot of the landscape iPad
# keyboard in the email layout (which is why "@" is on the main layer rather
# than behind .?123). If the keyboard layout or the device changes, re-measure:
# screenshot, find each key centre in the 2388x1668 landscape image, and update
# the table.
set -uo pipefail

# The SSH hop to the machine the iPad is plugged into comes from
# tools/device.env, which is not committed. Start from tools/device.env.example.
ENV_FILE="$(dirname "$0")/device.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
: "${JUMP_HOST:?set JUMP_HOST in tools/device.env (see tools/device.env.example)}"
HOST_SSH=(ssh -o ConnectTimeout=10 -o BatchMode=yes -p "${JUMP_PORT:-22}" "$JUMP_HOST")
# Overridable for the same reason as deploy-to-ipad.sh: the device allows one
# usbmux forward at a time, so whichever port is NOT the live one accepts the
# connection and then resets it.
IPAD_SSH_PORT="${IPAD_SSH_PORT:-22222}"
IPAD_SSH="ssh -i ~/.ssh/ipad_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=no -p ${IPAD_SSH_PORT} root@127.0.0.1"

# The key table below was measured with the iPad one way round. Turn the
# device end-for-end -- which happens whenever somebody picks it up -- and
# every coordinate is mirrored in both axes while the screenshot still looks
# identical, so the taps land on the wrong keys with nothing to show why.
# IPAD_FLIPPED=1 mirrors them back.
IPAD_FLIPPED="${IPAD_FLIPPED:-0}"
TOUCHSIM=/var/jb/usr/local/bin/touchsim

# Landscape screen coordinates (2388x1668) of each key centre.
# touchsim wants 0..1 in NATIVE PORTRAIT, so a landscape point (xl, yl) maps to
#   nx = (1667 - yl) / 1668      ny = xl / 2388
declare -A KEY_X KEY_Y
row1="q:342 w:531 e:720 r:909 t:1098 y:1287 u:1476 i:1665 o:1854 p:2043"
row2="a:408 s:597 d:786 f:975 g:1164 h:1353 j:1542 k:1731 l:1920"
row3="z:495 x:684 c:873 v:1062 b:1251 n:1440 m:1629 @:1818 .:2007"

for pair in $row1; do KEY_X[${pair%%:*}]=${pair##*:}; KEY_Y[${pair%%:*}]=1017; done
for pair in $row2; do KEY_X[${pair%%:*}]=${pair##*:}; KEY_Y[${pair%%:*}]=1191; done
for pair in $row3; do KEY_X[${pair%%:*}]=${pair##*:}; KEY_Y[${pair%%:*}]=1362; done

# The space bar, added when this script was first asked to type PROSE rather
# than a password. Measured the same way as the rows above and checked
# against them: row 3 lands on y 1362 and "@" on x 1818 in the same
# screenshot, both of which match the table, so the frame is the same one.
#
# Still no comma and still no uppercase. Comma is behind ".?123" on the
# email keyboard, which is a layer switch and a second set of coordinates;
# uppercase is refused on purpose (see below).
KEY_X[" "]=1057; KEY_Y[" "]=1533

usage() { echo "usage: $0 --var ENV_VAR_NAME   (never pass the value itself)" >&2; exit 2; }
[ "${1:-}" = "--var" ] || usage
VAR="${2:-}"; [ -n "$VAR" ] || usage
VALUE="${!VAR:-}"
if [ -z "$VALUE" ]; then
    echo "error: \$$VAR is empty or unset. Did you source your secrets file?" >&2
    exit 1
fi

# Build the whole tap sequence first, then send it in ONE ssh call. Sending a
# tap per connection would take a minute and give the field time to lose focus.
SEQUENCE=""
UNSUPPORTED=""
for (( i=0; i<${#VALUE}; i++ )); do
    ch="${VALUE:i:1}"
    # NOT lowercased. Silently folding case would type a DIFFERENT password
    # and the failure would look exactly like a typo, sending someone off to
    # regenerate a credential that was correct. Shift is not mapped, so an
    # uppercase character is refused loudly instead.
    # Quoted subscript: an unquoted space would be swallowed as word
    # splitting and the space bar would read as a missing key.
    x="${KEY_X["$ch"]:-}"
    y="${KEY_Y["$ch"]:-}"
    if [ -z "$x" ]; then
        # Collect the CHARACTER CLASS, never the character, so an error
        # message cannot leak part of the secret.
        case "$ch" in
            [0-9]) UNSUPPORTED="${UNSUPPORTED}digit " ;;
            [A-Z]) UNSUPPORTED="${UNSUPPORTED}uppercase " ;;
            *)     UNSUPPORTED="${UNSUPPORTED}symbol " ;;
        esac
        continue
    fi
    nx=$(awk -v y="$y" -v f="$IPAD_FLIPPED" \
         'BEGIN{v=(1667-y)/1668; if (f=="1") v=1-v; printf "%.4f", v}')
    ny=$(awk -v x="$x" -v f="$IPAD_FLIPPED" \
         'BEGIN{v=x/2388; if (f=="1") v=1-v; printf "%.4f", v}')
    # 2>&1, not just >/dev/null. touchsim echoes "tap <x> <y>" to STDERR, and
    # because the key table above is deterministic those coordinates decode
    # straight back to the characters typed. Redirecting only stdout leaked a
    # password into a terminal transcript once; it will not do so again.
    SEQUENCE="${SEQUENCE}${TOUCHSIM} tap ${nx} ${ny} >/dev/null 2>&1; sleep 0.35; "
done

if [ -n "$UNSUPPORTED" ]; then
    echo "error: \$$VAR contains characters this script cannot type: $UNSUPPORTED" >&2
    echo "       Only a-z, @ and . are on the email keyboard's main layer." >&2
    echo "       Digits and symbols need the .?123 layer, which is not mapped yet." >&2
    exit 1
fi

echo "typing ${#VALUE} characters (value not shown)…" >&2
# The sequence travels over stdin, not argv, so it never appears in `ps`.
printf '%s\n' "$SEQUENCE" | "${HOST_SSH[@]}" "$IPAD_SSH 'bash -s'" >/dev/null
echo "done" >&2
