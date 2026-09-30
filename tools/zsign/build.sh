#!/usr/bin/env bash
# build.sh — build the zsign this project signs with: upstream v1.1.2 plus
# bundle-entitlements.patch, which adds `-X KEY=FILE`.
#
# Why a patched signer at all. Stock zsign takes ONE `-e` for the whole
# archive, so the share extension came out claiming the app's
# application-identifier (`…blackmail`) while its bundle id is
# `…blackmail.share`, and iOS refuses that. Signing the extension on its own
# first does not help: signing the app re-signs everything nested in it.
# `-X` gives a nested bundle, named by bundle id or by its path inside the
# .app, its own entitlements file, embeds the profile in it as Xcode would,
# and fails when a KEY matches nothing. See docs/TOOLCHAIN.md.
#
#   tools/zsign/build.sh                 # into /mnt/build/zsign-blackmail
#   ZSIGN_PREFIX=~/opt/zsign tools/zsign/build.sh
#
# Needs git, g++, make, pkg-config and OpenSSL 3's headers. Nothing is
# installed system-wide; `rm -rf "$ZSIGN_PREFIX"` undoes it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${ZSIGN_PREFIX:-/mnt/build/zsign-blackmail}"
UPSTREAM=https://github.com/zhlynn/zsign
TAG=v1.1.2
# The commit the tag names today. Checked, so a moved tag cannot quietly
# change what the patch is applied to.
COMMIT=614caa8d1ca949e260e5746144aa52d27a4b08d6

mkdir -p "$PREFIX"
SRC="$PREFIX/src"
if [ ! -d "$SRC/.git" ]; then
    git clone --quiet "$UPSTREAM" "$SRC"
fi
git -C "$SRC" fetch --quiet --tags
git -C "$SRC" checkout --quiet --force "$COMMIT"
git -C "$SRC" clean --quiet -fdx
[ "$(git -C "$SRC" rev-parse "$TAG^{}")" = "$COMMIT" ] \
    || echo "note: $TAG no longer names $COMMIT upstream; building $COMMIT" >&2
git -C "$SRC" apply "$HERE/bundle-entitlements.patch"

make -C "$SRC/build/linux" -j"$(nproc)" VERSION="1.1.2+bundle-entitlements" >/dev/null
mkdir -p "$PREFIX/bin"
install -m 755 "$SRC/bin/zsign" "$PREFIX/bin/zsign"

# The option is the whole point of this build; refuse to report success
# without it. `-h` exits non-zero, hence the `|| true`.
HELP=$("$PREFIX/bin/zsign" -h 2>&1 || true)
case "$HELP" in
  *--bundle_entitlements*) ;;
  *) echo "error: built zsign has no -X" >&2; exit 1 ;;
esac
echo "==> $("$PREFIX/bin/zsign" -v)  $PREFIX/bin/zsign"
