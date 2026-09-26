#!/usr/bin/env bash
# provision-ipad.sh — put Blackmail on a NEW iPad, in one command, at his house.
#
# The problem this solves. The app is signed with an AD-HOC profile, and an
# ad-hoc build launches only on UDIDs that were baked into the profile when it
# was generated. The ad-hoc profile currently contains exactly one device — the
# dev iPad. So the build that works perfectly here will not launch on his iPad
# at all, and the fix needs his UDID, which is not shown anywhere in Settings.
#
# The visit is therefore: plug in, read the UDID, register it with Apple,
# regenerate the profile, re-sign, install. Six steps, each with its own way of
# going wrong, in somebody's kitchen. This does them in order and stops with a
# plain sentence when it cannot.
#
#   ./provision-ipad.sh --check     # run BEFORE the visit, at home, no iPad
#   ./provision-ipad.sh             # run AT the visit, iPad plugged in
#
# --check is the important half. Every failure this script can hit is cheaper
# to find at home than at his house, and the two known gaps (no ideviceinstaller
# on the laptop, no App Store Connect key anywhere) are both of that kind.
set -uo pipefail

# Machine-specific values (signing directory, profile file and name) come from
# tools/device.env, which is not committed. Start from tools/device.env.example.
ENV_FILE="$(dirname "$0")/device.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

SIGN="${SIGN_DIR:-$HOME/.apple-signing}"
IPA="${IPA:-$HOME/Blackmail.ipa}"
PROFILE="$SIGN/${PROFILE_FILE:-adhoc.mobileprovision}"
PROFILE_NAME="${PROFILE_NAME:-the ad-hoc profile}"
OUT="${OUT_DIR:-$HOME/blackmail-provision}"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAILED=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
FAILED=0

# ---------------------------------------------------------------- pre-flight

step "Pre-flight"

for t in idevice_id ideviceinfo zsign curl python3 unzip zip openssl; do
    command -v "$t" >/dev/null && ok "$t" || bad "$t is missing — install it"
done
# The one that is actually absent on the laptop today. Without it the IPA can
# be signed and then not installed, which is the worst place to stop.
if command -v ideviceinstaller >/dev/null; then ok "ideviceinstaller"
else bad "ideviceinstaller is missing — REQUIRED to install on a non-jailbroken iPad
       Arch: sudo pacman -S ideviceinstaller     Debian/Ubuntu: sudo apt install ideviceinstaller"
fi

[ -f "$SIGN/ios_distribution.key" ] && ok "signing key" || bad "no $SIGN/ios_distribution.key — copy the signing directory from the build host"
[ -f "$SIGN/ios_distribution.pem" ] && ok "signing cert" || bad "no $SIGN/ios_distribution.pem"
[ -f "$PROFILE" ]                   && ok "provisioning profile" || bad "no $PROFILE"
[ -f "$SIGN/blackmail.entitlements" ] && ok "entitlements" || bad "no $SIGN/blackmail.entitlements"
[ -f "$IPA" ] && ok "IPA to install ($(du -h "$IPA" | cut -f1))" \
             || bad "no IPA at $IPA — build one first and copy it here (IPA=… to override)"

# Certificate and profile die at the same instant. Say how long is left, because
# a year is not very long when the device belongs to somebody who cannot re-sign.
if [ -f "$SIGN/ios_distribution.pem" ]; then
    END=$(openssl x509 -in "$SIGN/ios_distribution.pem" -noout -enddate | cut -d= -f2)
    DAYS=$(( ( $(date -d "$END" +%s) - $(date +%s) ) / 86400 ))
    if   [ "$DAYS" -lt 0 ];  then bad  "certificate EXPIRED $(( -DAYS )) days ago — nothing will launch"
    elif [ "$DAYS" -lt 45 ]; then warn "certificate expires in $DAYS days ($END) — renew before installing on his iPad"
    else ok "certificate valid for $DAYS more days ($END)"; fi
fi

# App Store Connect credentials are optional: with them the device is registered
# automatically, without them the script hands you the UDID and waits.
ASC=0
if [ -n "${ASC_P8:-}" ] && [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
    ASC=1; ok "App Store Connect API credentials present — registration will be automatic"
else
    warn "no ASC_P8 / ASC_KEY_ID / ASC_ISSUER_ID — registration will be MANUAL.
       The key that used to be here is gone: asc_jwt.py survives but there is no
       .p8 on this machine or on the build host. Either reissue one (App Store Connect
       → Users and Access → Integrations → App Store Connect API; the .p8
       downloads ONCE) or plan to add the UDID by hand in the portal."
fi

profile_udids() {
    openssl smime -inform der -verify -noverify -in "$PROFILE" 2>/dev/null \
    | python3 -c "
import plistlib,sys
# loadS, not load: a pipe is not seekable and plistlib.load() seeks. Getting
# this wrong reported 'authorises 0 devices' and, far worse, made the
# after-you-fixed-it check below fail forever — an unwinnable loop in
# somebody's kitchen.
d=plistlib.loads(sys.stdin.buffer.read())
print('\n'.join(d.get('ProvisionedDevices') or []))"
}
if [ -f "$PROFILE" ]; then
    N=$(profile_udids | grep -c . || true)
    ok "profile currently authorises $N device(s)"
fi

if [ "$CHECK_ONLY" = 1 ]; then
    echo
    [ "$FAILED" = 0 ] && echo "Pre-flight PASSED — ready for the visit." \
                      || echo "Pre-flight FAILED — fix the ✗ lines BEFORE you go."
    exit "$FAILED"
fi
[ "$FAILED" = 0 ] || { echo; echo "Stopping: pre-flight failed. Run --check at home next time."; exit 1; }

# ------------------------------------------------------------------- the iPad

step "Waiting for an iPad"
for i in $(seq 1 60); do
    UDID=$(idevice_id -l 2>/dev/null | head -1)
    [ -n "$UDID" ] && break
    sleep 1
done
[ -n "${UDID:-}" ] || { echo "No device after 60s. Unlock it and tap Trust."; exit 1; }

NAME=$(ideviceinfo -u "$UDID" -k DeviceName 2>/dev/null)
VER=$(ideviceinfo  -u "$UDID" -k ProductVersion 2>/dev/null)
MODEL=$(ideviceinfo -u "$UDID" -k ProductType 2>/dev/null)
mkdir -p "$OUT"
printf '%s\n' "$UDID" > "$OUT/udid.txt"

echo
printf '\033[1m  UDID   %s\033[0m\n' "$UDID"
printf '  name   %s\n  model  %s\n  iOS    %s\n' "$NAME" "$MODEL" "$VER"
echo "  (also written to $OUT/udid.txt)"

# The one fact that decides whether this ever has to be done again.
case "$VER" in
  1[0-6].*|17.0|17.0.*) echo "  → iOS $VER is in TrollStore range: a permanent install with NO expiry
    is possible, and would spare him the annual re-signing entirely." ;;
  *) echo "  → iOS $VER is past TrollStore. Certificate signing it is, which means
    this app STOPS LAUNCHING when the profile expires. Diarise it." ;;
esac

# --------------------------------------------------------------- registration

if profile_udids | grep -qx "$UDID"; then
    step "Already authorised"
    ok "this iPad is already in the profile — skipping registration"
else
    step "Registering the device"
    if [ "$ASC" = 1 ]; then
        TOKEN=$(python3 "$SIGN/asc_jwt.py") || { echo "could not mint an ASC token"; exit 1; }
        CODE=$(curl -s -o "$OUT/register.json" -w '%{http_code}' \
            -X POST 'https://api.appstoreconnect.apple.com/v1/devices' \
            -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
            -d "{\"data\":{\"type\":\"devices\",\"attributes\":{\"name\":$(python3 -c "import json,sys;print(json.dumps(sys.argv[1]))" "${NAME:-Sam iPad}"),\"udid\":\"$UDID\",\"platform\":\"IOS\"}}}")
        # 409 means it is already registered on the account, which is a success
        # for our purposes and must not stop the visit.
        case "$CODE" in
          20*) ok "registered with Apple" ;;
          409) ok "already registered on the account" ;;
          *)   bad "registration failed (HTTP $CODE) — see $OUT/register.json"
               echo "     Add the UDID by hand in the portal, then re-run."; exit 1 ;;
        esac
        echo
        echo "  A profile cannot have devices added to it — it must be REPLACED."
        echo "  In the portal: Profiles → '$PROFILE_NAME' → Edit → tick this device"
        echo "  → Save → Download, and put the file at:"
        echo "      $PROFILE"
        echo "  (the API can do this too, but deleting and recreating a working"
        echo "   profile unattended, in somebody's house, is not a good trade)"
    else
        echo "  Add this UDID in the developer portal now:"
        echo
        printf '      \033[1m%s\033[0m\n' "$UDID"
        echo
        echo "  Devices → + → paste the UDID → Continue → Register"
        echo "  Profiles → '$PROFILE_NAME' → Edit → tick the new device → Save"
        echo "  → Download, and put the file at:"
        echo "      $PROFILE"
    fi
    echo
    read -r -p "  Press Enter once the new profile is in place (Ctrl-C to abandon) "
    if ! profile_udids | grep -qx "$UDID"; then
        echo "  That profile still does not list this iPad. Nothing installed."
        exit 1
    fi
    ok "profile now authorises this iPad"
fi

# -------------------------------------------------------------- sign, install

step "Signing"
cp -f "$IPA" "$OUT/Blackmail-signed.ipa"
zsign -q -k "$SIGN/ios_distribution.key" -c "$SIGN/ios_distribution.pem" \
      -m "$PROFILE" -e "$SIGN/blackmail.entitlements" \
      "$OUT/Blackmail-signed.ipa" || { echo "zsign failed"; exit 1; }
ok "signed"

step "Installing"
ideviceinstaller -u "$UDID" -i "$OUT/Blackmail-signed.ipa" || {
    echo "Install failed. The usual causes, in order of likelihood:"
    echo "  - the iPad is locked (unlock it and re-run)"
    echo "  - the profile does not actually contain this UDID"
    echo "  - a different signature for the same bundle id is already installed"
    echo "    (delete Blackmail from the iPad and re-run)"
    exit 1; }
ok "installed"

step "Done"
echo "  Launch Blackmail on the iPad and set the account up in its own form:"
echo "  his address and a Gmail APP password (not his normal one)."
echo
echo "  Then check the signature. If it is missing, this iPad cannot receive it"
echo "  the way the dev one does — signatureHTML and the inline logo live in the"
echo "  app container and no screen in the app can set them. See B-035."
