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

# The share extension (B-036 spike). A second signed bundle inside PlugIns/,
# which nothing on this Xcode-less pipeline had ever produced. Its executable
# is linked with `-e _NSExtensionMain` (see Package.swift) so the entry point
# is Foundation's, not the one SwiftPM generates.
#
# Guarded rather than assumed: if the extension did not build, the app is
# still packaged and installable, because an app that ships without its share
# sheet beats no app at all.
#
# OPT-IN, and that is not caution for its own sake. zsign takes ONE `-e` for
# the whole archive, so the extension is currently signed with the APP's
# `application-identifier` (`…blackmail`) while its bundle id is
# `…blackmail.share`. iOS wants those to match. The copy-based deploy to the
# dev iPad never exercises that — it writes files into an existing bundle and
# installd is never involved — but `provision-ipad.sh` does a REAL install on
# his iPad, and an extension with a mismatched identifier is exactly the sort
# of thing installd rejects. Shipping an unverified .appex by default would
# risk the one install that matters, to gain a feature that does not work yet.
EXT_BIN=".build/arm64-apple-ios/release/BlackmailShare"
if [ "${BLACKMAIL_SHARE_EXT:-0}" = 1 ] && [ -f "$EXT_BIN" ]; then
    stale_against "$EXT_BIN" Sources/BlackmailShare
    APPEX="$APP/PlugIns/BlackmailShare.appex"
    mkdir -p "$APPEX"
    cp "$EXT_BIN" "$APPEX/BlackmailShare"
    llvm-strip --strip-all "$APPEX/BlackmailShare" 2>/dev/null || true
    cp Resources/ShareInfo.plist "$APPEX/Info.plist"
    echo "==> bundled PlugIns/BlackmailShare.appex"
elif [ "${BLACKMAIL_SHARE_EXT:-0}" = 1 ]; then
    echo "==> WARNING: BLACKMAIL_SHARE_EXT=1 but no $EXT_BIN — packaging WITHOUT it" >&2
fi

( cd "$OUT" && rm -f ../Blackmail-unsigned.ipa && zip -qr9 ../Blackmail-unsigned.ipa Payload )
echo "==> $(ls -lh Blackmail-unsigned.ipa | awk '{print $5}')  Blackmail-unsigned.ipa"
unzip -l Blackmail-unsigned.ipa | tail -3
