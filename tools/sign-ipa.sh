#!/usr/bin/env bash
# sign-ipa.sh — sign an IPA the one way this project signs, then prove it.
#
#   tools/sign-ipa.sh UNSIGNED.ipa SIGNED.ipa
#
# Every bundle gets its own entitlements, from ios/Resources. Without the
# share extension the app gets Blackmail.entitlements, the same entitlements
# every build before the extension was signed with and proven on his iPad.
# With it, the app gets BlackmailWithShare.entitlements, which adds the
# Keychain group the two share, and the extension its
# BlackmailShare.entitlements through zsign's -X. That option exists only
# in the patched zsign (tools/zsign/build.sh); stock zsign would sign the
# extension as the app, which iOS refuses (B-036), so without it an IPA
# with an extension is not signed at all.
#
# Then tools/check-signature.py reads every signature back out of the result
# and this fails unless each bundle names itself and the seal holds. A signed
# IPA that installd would refuse is found here, not on his iPad.
#
# Deploy and provision both sign through this. The signing files come from
# SIGN_DIR (default ~/.apple-signing) and PROFILE_FILE, as in device.env.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/tools/device.env" ] && . "$ROOT/tools/device.env"
IN="${1:?usage: sign-ipa.sh UNSIGNED.ipa SIGNED.ipa}"
OUT="${2:?usage: sign-ipa.sh UNSIGNED.ipa SIGNED.ipa}"
SIGN="${SIGN_DIR:-$HOME/.apple-signing}"
PROFILE="$SIGN/${PROFILE_FILE:-adhoc.mobileprovision}"
RES="$ROOT/ios/Resources"

# zsign's own temporary folder and the checker's, kept beside the output
# rather than in /tmp, which is small on the build host.
SCRATCH="$(dirname "$(realpath -m "$OUT")")/.sign-scratch.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

# `-h` exits non-zero, so its output is matched rather than piped under
# pipefail.
has_x() {
    case "$("$1" -h 2>&1 || true)" in *--bundle_entitlements*) return 0 ;; esac
    return 1
}
ZSIGN="${ZSIGN:-}"
if [ -z "$ZSIGN" ]; then
    for candidate in /mnt/build/zsign-blackmail/bin/zsign "$(command -v zsign || true)"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ] && has_x "$candidate"; then
            ZSIGN="$candidate"; break
        fi
    done
fi

EXTENSION=$(unzip -Z1 "$IN" | grep -m1 -E '^Payload/[^/]+\.app/PlugIns/[^/]+\.appex/Info\.plist$' || true)
ARGS=(-e "$RES/Blackmail.entitlements")
if [ -n "$EXTENSION" ]; then
    if [ -z "$ZSIGN" ] || ! has_x "$ZSIGN"; then
        echo "error: $IN carries an app extension and ${ZSIGN:-no zsign here} has no -X." >&2
        echo "       Build the patched one: tools/zsign/build.sh" >&2
        exit 1
    fi
    ARGS=(-e "$RES/BlackmailWithShare.entitlements"
          -X "wtf.uhoh.blackmail.share=$RES/BlackmailShare.entitlements")
fi
ZSIGN="${ZSIGN:-zsign}"

rm -f "$OUT"
"$ZSIGN" -q -t "$SCRATCH" -k "$SIGN/ios_distribution.key" -c "$SIGN/ios_distribution.pem" \
      -m "$PROFILE" "${ARGS[@]}" -o "$OUT" "$IN"
[ -f "$OUT" ] || { echo "error: zsign wrote no $OUT" >&2; exit 1; }

CHECK=(python3 "$ROOT/tools/check-signature.py" "$OUT")
[ -n "$EXTENSION" ] && CHECK+=(--require-extension)
if ! CHECK_SIGNATURE_SCRATCH="$SCRATCH" "${CHECK[@]}" > "$SCRATCH/check.log"; then
    grep -E 'FAIL' "$SCRATCH/check.log" >&2
    echo "error: $OUT is not signed as it must be; see above" >&2
    rm -f "$OUT"
    exit 1
fi
echo "==> signed $(basename "$OUT")${EXTENSION:+, with the share extension}: $(tail -1 "$SCRATCH/check.log")"
