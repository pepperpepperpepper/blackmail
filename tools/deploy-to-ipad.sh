#!/usr/bin/env bash
# deploy-to-ipad.sh — build, sign, install on the dev iPad, and PROVE it landed.
#
# Written after debugging a UI bug for four rounds against a binary that had
# never been deployed. The deploy step had been typed by hand each time with
# its output suppressed, so a silent failure looked exactly like a fix that
# did not work. Every conclusion drawn in those rounds was worthless.
#
# So this script's real job is the md5 comparison at the end. Everything else
# is convenience.
set -euo pipefail

cd "$(dirname "$0")/.."
# Machine-specific values — the SSH hop to the machine the iPad is plugged
# into, the app's container path on the device, the signing files — live in
# tools/device.env, which is not committed. Start from tools/device.env.example.
[ -f tools/device.env ] && . tools/device.env
: "${JUMP_HOST:?set JUMP_HOST in tools/device.env (see tools/device.env.example)}"
: "${IPAD_BUNDLE_PATH:?set IPAD_BUNDLE_PATH in tools/device.env}"
IOS=ios
SIGN="${SIGN_DIR:-$HOME/.apple-signing}"
BUNDLE="$IPAD_BUNDLE_PATH"
HOST=(ssh -o ConnectTimeout=10 -o BatchMode=yes -p "${JUMP_PORT:-22}" "$JUMP_HOST")
# The usbmux forwarder's port. 22222 is the usual iproxy one, but the device
# appears to allow only ONE forward at a time, so when the screenshot tool's
# pymobiledevice3 forward (2223) is the live one, iproxy on 22222 accepts the
# TCP connection and then resets it — which looks like the iPad being down and
# is not. Override rather than edit: IPAD_SSH_PORT=2223 ./tools/deploy-to-ipad.sh
IPAD_SSH_PORT="${IPAD_SSH_PORT:-22222}"
IPAD="ssh -i ~/.ssh/ipad_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=no -p ${IPAD_SSH_PORT} root@127.0.0.1"

RELAUNCH=1
[ "${1:-}" = "--no-launch" ] && RELAUNCH=0

# `-c release`, which was not always here. A plain (debug) build no longer
# LINKS for iOS: Swift 6.2 emits calls to `swift_coroFrameAlloc` for
# coroutine accessors, that symbol does not exist in the iOS 16.5 runtime
# this app deploys against, and only the optimiser removes the calls. So
# debug failed at the link step with `undefined symbol: swift_coroFrameAlloc`
# while release built clean.
#
# That mattered here and nowhere else: this step is only a fast error check,
# but it runs under `set -e` with `pipefail`, so its failure aborted the
# whole deploy before anything was packaged. Release is also the only
# configuration that has ever shipped — package.sh builds `-c release` and
# copies from `.build/arm64-apple-ios/release` — so checking debug was
# checking a configuration the product does not use.
echo "==> build"
( cd "$IOS" && source /mnt/build/apple-toolchain/env.sh 2>/dev/null
  swift build --swift-sdk ios165 -c release 2>&1 | grep -E 'error:|Build complete' )

echo "==> package and sign"
( cd "$IOS" && source /mnt/build/apple-toolchain/env.sh 2>/dev/null
  bash package.sh >/dev/null
  zsign -q -k "$SIGN/ios_distribution.key" -c "$SIGN/ios_distribution.pem" \
        -m "$SIGN/${PROFILE_FILE:-adhoc.mobileprovision}" -e "$SIGN/blackmail.entitlements" \
        -o Blackmail.ipa Blackmail-unsigned.ipa >/dev/null 2>&1
  python3 "$SIGN/verify-ipa.py" Blackmail.ipa | tail -1 )

# The binary inside the SIGNED ipa, which is literally what gets copied to
# the device. Two earlier attempts at this comparison were wrong and both
# reported a false failure: the raw build product differs because package.sh
# strips it, and the stripped copy differs because zsign then embeds a
# signature (which also makes it change on every run, so it cannot be
# compared across builds either).
SIGNED_TMP=$(mktemp -d)
trap 'rm -rf "$SIGNED_TMP"' EXIT
unzip -qo "$IOS/Blackmail.ipa" -d "$SIGNED_TMP"
LOCAL_MD5=$(md5sum "$SIGNED_TMP/Payload/Blackmail.app/Blackmail" | cut -d' ' -f1)

echo "==> copy"
# Straight down the SSH hop, never through a public URL: the signed IPA
# embeds the provisioning profile, and with it the device list and the
# name on the signing certificate.
timeout 180 "${HOST[@]}" 'cat > ~/Blackmail.ipa' < "$IOS/Blackmail.ipa"

echo "==> install"
"${HOST[@]}" "
set -e
cd ~
rm -rf bmstage && mkdir bmstage && cd bmstage && unzip -q ../Blackmail.ipa
tar czf ~/bmapp.tgz -C Payload Blackmail.app
cat ~/bmapp.tgz | $IPAD '
  killall Blackmail 2>/dev/null
  cat > /var/jb/var/root/bmapp.tgz
  cd /var/jb/var/root && rm -rf Blackmail.app && tar xzf bmapp.tgz 2>/dev/null
  cp -a /var/jb/var/root/Blackmail.app/. $BUNDLE/
  chmod 755 $BUNDLE/Blackmail
  chown -R _installd:_installd $BUNDLE
'" >/dev/null

# THE POINT OF THIS SCRIPT.
REMOTE_MD5=$("${HOST[@]}" "$IPAD 'md5sum $BUNDLE/Blackmail'" 2>/dev/null | cut -d' ' -f1)
if [ "$LOCAL_MD5" != "$REMOTE_MD5" ]; then
    echo "FAILED: the binary on the device is not the one just built." >&2
    echo "  local  $LOCAL_MD5" >&2
    echo "  device $REMOTE_MD5" >&2
    exit 1
fi
echo "==> verified on device: $REMOTE_MD5"

if [ "$RELAUNCH" = 1 ]; then
    # WAKE THE SCREEN FIRST. SpringBoard will not foreground an app onto a
    # dark display: uiopen still exits 0, nothing launches, and no crash log
    # is written — so a deploy that had in fact succeeded reported "FAILED:
    # not running" and sent me hunting a launch crash that never happened.
    # shotc2 is the screenshot daemon's client and calls SBSUndimScreen()
    # before capturing, which is the only wake path this box has.
    #
    # Then uiopen up to three times: one call after a kill frequently does
    # not bring the app to the front even with the screen on.
    "${HOST[@]}" "$IPAD '
      /var/jb/usr/local/bin/shotc2 >/dev/null 2>&1
      sleep 1
      n=0
      for i in 1 2 3; do
        /var/jb/usr/bin/uiopen --bundleid wtf.uhoh.blackmail
        sleep 6
        n=\$(ps aux | grep -i blackmai | grep -v grep | wc -l)
        [ \"\$n\" -ge 1 ] && break
      done
      echo \$n'" 2>/dev/null | tail -1 \
        | while read -r n; do
            [ "$n" -ge 1 ] && echo "==> running" || { echo "FAILED: not running" >&2; exit 1; }
          done
fi
