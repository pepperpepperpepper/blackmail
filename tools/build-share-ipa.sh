#!/usr/bin/env bash
# build-share-ipa.sh — the IPA for the one check B-036 still needs on glass:
# that the share extension is REGISTERED, and shows in the share sheet.
#
# The dev iPad's deploy (deploy-to-ipad.sh) copies files into a bundle that
# is already installed, and plugins are registered at install time, by
# installd, so that deploy can never show the extension however right it is.
# This IPA has to go through a real install:
#
#   ideviceinstaller -i ios/Blackmail-share.ipa   # iPad on USB; its UDID is in the profile
#
# or TrollStore on the iPad, which keeps each bundle's entitlements as
# signed. Then open Blackmail once (that hands the account to the
# extension), share a page from Safari, and look for Blackmail in the row of
# apps. The IPA embeds the profile, with its device list and the name on
# the certificate: move it over SSH, never through a public URL.
set -euo pipefail
cd "$(dirname "$0")/.."

( cd ios && source /mnt/build/apple-toolchain/env.sh 2>/dev/null
  swift build --swift-sdk ios165 -c release 2>&1 | grep -E 'error:|Build complete'
  BLACKMAIL_SHARE_EXT=1 bash package.sh >/dev/null )

unzip -Z1 ios/Blackmail-unsigned.ipa \
    | grep -q '^Payload/Blackmail.app/PlugIns/BlackmailShare.appex/BlackmailShare$' \
    || { echo "error: the extension was not packaged" >&2; exit 1; }
tools/sign-ipa.sh ios/Blackmail-unsigned.ipa ios/Blackmail-share.ipa
sha256sum ios/Blackmail-share.ipa
