#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
svg="$repo_root/logo.svg"
master="$repo_root/assets/icon/icon.png"

# Fraction of the canvas the glyph occupies once its own built-in whitespace
# has been trimmed away; the rest is white margin.
padding_ratio=0.88
master_size=1024

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Render once at high resolution and trim the SVG's own margin, so "zoom" is
# measured against the actual glyph ink rather than its viewBox.
full="$tmp/full.png"
trimmed="$tmp/trimmed.png"
rsvg-convert -w "$master_size" -h "$master_size" "$svg" -o "$full"
magick "$full" -trim +repage "$trimmed"

content_size="$(awk -v s="$master_size" -v r="$padding_ratio" 'BEGIN { printf "%d", s * r }')"

mkdir -p "$(dirname "$master")"

# Resize the trimmed glyph, then flatten it onto an opaque white canvas
# (-alpha remove/off bakes the white in rather than leaving it transparent).
magick "$trimmed" -resize "${content_size}x${content_size}" \
    -background white -gravity center -extent "${master_size}x${master_size}" \
    -alpha remove -alpha off \
    "$master"

# optipng shrinks the file losslessly; exiftool strips the tEXt
# creation-time chunks ImageMagick embeds, which would otherwise make the
# output differ byte-for-byte between runs even with identical inputs.
optipng -o7 -quiet "$master"
exiftool -all= -overwrite_original -quiet "$master"

echo "wrote $master (${master_size}x${master_size}, glyph ${content_size}x${content_size})"

cd "$repo_root"
dart run flutter_launcher_icons
