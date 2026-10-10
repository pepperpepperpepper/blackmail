#!/usr/bin/env bash
# make-app-icons.sh — every ios/Resources/AppIcon*.png from the one picture
# in docs/icon/app-icon-source.png (D-018).
#
# The picture is a rounded tile on a clear margin. The square of the tile,
# 2 px in from its edge (the edge itself carries a faint line), is made
# opaque and resized to each file the app ships, at the file's own size.
# iOS rounds the corners itself. There is no asset catalog: loose PNGs,
# named in Info.plist, because actool does not run here.
#
# Needs ImageMagick 7 (magick). Run from anywhere; it writes the files in
# place and prints each one's size.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=docs/icon/app-icon-source.png
CROP=402x402+54+39            # the tile, 2 px in
GROUND='srgb(143,162,170)'    # under the tile's own rounded corners
TILE=$(mktemp --suffix=.png)
trap 'rm -f "$TILE"' EXIT
magick "$SRC" -crop "$CROP" +repage -background "$GROUND" -alpha remove -alpha off "$TILE"
for f in ios/Resources/AppIcon*.png; do
    size=$(magick identify -format '%wx%h' "$f")
    magick "$TILE" -filter Lanczos -resize "${size}!" -strip -define png:color-type=2 "$f"
    echo "$f $size"
done
