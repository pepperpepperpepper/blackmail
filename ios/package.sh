#!/bin/bash
# package.sh - build Blackmail and assemble an unsigned .ipa.
# There is no xcodebuild here, so the bundle is assembled by hand, in the shape
# already proven on this pipeline.
set -euo pipefail
cd "$(dirname "$0")"
. /mnt/build/apple-toolchain/env.sh

SDK="${BLACKMAIL_SDK:-ios165}"
swift build --swift-sdk "$SDK" -c release 2>&1 | grep -vE 'no version information available' | tail -3

# BlackmailApp, not Blackmail: the executable target was renamed when the
# code was split into a library (device + host, so the parsers are testable)
# plus a thin entry point. Pointing this at "Blackmail" would silently
# package the STALE binary left over from a previous build and report
# success -- the worst kind of release bug, because the artifact looks fine
# and is simply old.
BIN=".build/arm64-apple-ios/release/BlackmailApp"
OUT="build"
APP="$OUT/Payload/Blackmail.app"

if [ ! -f "$BIN" ]; then
    echo "error: $BIN does not exist - did the build actually run?" >&2
    exit 1
fi
# Refuse anything older than the newest source file, so a failed build can
# never be packaged as if it had succeeded.
#
# Compared against its OWN sources, not against all of Sources/. That
# distinction appeared the moment a second executable did: BlackmailApp does
# not depend on Sources/BlackmailShare, so touching the extension made the
# app look stale and aborted the whole package with a message that was true
# by its own logic and wrong about the world.
stale_against() {           # stale_against <binary> <source dir>...
    local bin="$1"; shift
    local newest
    newest=$(find "$@" -name '*.swift' -newer "$bin" -print -quit 2>/dev/null)
    if [ -n "$newest" ]; then
        echo "error: $bin is older than $newest - the build is stale" >&2
        exit 1
    fi
}
stale_against "$BIN" Sources/Blackmail Sources/BlackmailApp
rm -rf "$OUT"; mkdir -p "$APP"
cp "$BIN" "$APP/Blackmail"
llvm-strip --strip-all "$APP/Blackmail" 2>/dev/null || strip "$APP/Blackmail" 2>/dev/null || true
cp Resources/Info.plist "$APP/"
cp Resources/AppIcon*.png "$APP/"

# The share extension (B-036). A second bundle inside PlugIns/, its
# executable linked with `-e _NSExtensionMain` (see Package.swift) so the
# entry point is Foundation's, not the one SwiftPM generates. All its code is
# the Blackmail library's, so it is stale whenever the library is.
#
# Guarded rather than assumed: if the extension did not build, the app is
# still packaged and installable, because an app that ships without its share
# sheet beats no app at all.
#
# Still OPT-IN, for one reason now. Signing is solved: tools/sign-ipa.sh
# gives the extension its own application-identifier with the patched zsign's
# -X and refuses any IPA where a bundle does not name itself. What has never
# happened is the extension being REGISTERED on a device, because the dev
# iPad's copy-based deploy never goes through installd, which is where
# plugins are registered. Until one real install has shown it in the share
# sheet, his iPad's install (provision-ipad.sh) is not where to find out.
EXT_BIN=".build/arm64-apple-ios/release/BlackmailShare"
if [ "${BLACKMAIL_SHARE_EXT:-0}" = 1 ] && [ -f "$EXT_BIN" ]; then
    stale_against "$EXT_BIN" Sources/Blackmail Sources/BlackmailShare
    APPEX="$APP/PlugIns/BlackmailShare.appex"
    mkdir -p "$APPEX"
    cp "$EXT_BIN" "$APPEX/BlackmailShare"
    llvm-strip --strip-all "$APPEX/BlackmailShare" 2>/dev/null || true
    cp Resources/ShareInfo.plist "$APPEX/Info.plist"
    # The app's version numbers, which an extension's have to match. Taken
    # from the app's Info.plist at packaging so the two cannot drift.
    python3 - "$APP/Info.plist" "$APPEX/Info.plist" <<'PY'
import plistlib, sys
app = plistlib.load(open(sys.argv[1], "rb"))
ext = plistlib.load(open(sys.argv[2], "rb"))
for key in ("CFBundleShortVersionString", "CFBundleVersion"):
    ext[key] = app[key]
plistlib.dump(ext, open(sys.argv[2], "wb"))
PY
    echo "==> bundled PlugIns/BlackmailShare.appex"
elif [ "${BLACKMAIL_SHARE_EXT:-0}" = 1 ]; then
    echo "==> WARNING: BLACKMAIL_SHARE_EXT=1 but no $EXT_BIN — packaging WITHOUT it" >&2
fi

( cd "$OUT" && rm -f ../Blackmail-unsigned.ipa && zip -qr9 ../Blackmail-unsigned.ipa Payload )
echo "==> $(ls -lh Blackmail-unsigned.ipa | awk '{print $5}')  Blackmail-unsigned.ipa"
unzip -l Blackmail-unsigned.ipa | tail -3
