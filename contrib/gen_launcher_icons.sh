#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
svg="$repo_root/logo.svg"
master="$repo_root/assets/icon/icon.png"
foreground="$repo_root/assets/icon/icon_foreground.png"

# Fraction of the canvas the glyph occupies once its own built-in whitespace
# has been trimmed away; the rest is margin. The flat legacy icon (pre-Android
# 8, and the fallback other launchers draw as-is) can zoom in close since
# nothing crops it. The adaptive foreground has to stay well inside Android's
# "safe zone" -- only the centered 66%-diameter circle of the 108dp adaptive
# canvas is guaranteed visible once a launcher masks it into a circle,
# squircle, teardrop, etc. -- so it's zoomed out a lot further, on top of the
# tool's own default 16% inset.
padding_ratio=0.88
foreground_padding_ratio=0.55
master_size=1024

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Render once at high resolution and trim the SVG's own margin, so "zoom" is
# measured against the actual glyph ink rather than its viewBox.
full="$tmp/full.png"
trimmed="$tmp/trimmed.png"
rsvg-convert -w "$master_size" -h "$master_size" "$svg" -o "$full"
magick "$full" -trim +repage "$trimmed"

mkdir -p "$(dirname "$master")"

content_size="$(awk -v s="$master_size" -v r="$padding_ratio" 'BEGIN { printf "%d", s * r }')"

# Resize the trimmed glyph, then flatten it onto an opaque white canvas
# (-alpha remove/off bakes the white in rather than leaving it transparent).
# This is the flat legacy icon.
magick "$trimmed" -resize "${content_size}x${content_size}" \
    -background white -gravity center -extent "${master_size}x${master_size}" \
    -alpha remove -alpha off \
    "$master"

fg_content_size="$(awk -v s="$master_size" -v r="$foreground_padding_ratio" 'BEGIN { printf "%d", s * r }')"

# Same glyph, but left transparent (no background baked in) and zoomed out
# further -- this is the adaptive icon foreground layer, composited over
# adaptive_icon_background at runtime and masked into the launcher's shape.
magick "$trimmed" -resize "${fg_content_size}x${fg_content_size}" \
    -background none -gravity center -extent "${master_size}x${master_size}" \
    "$foreground"

for f in "$master" "$foreground"; do
    # optipng shrinks the file losslessly; exiftool strips the tEXt
    # creation-time chunks ImageMagick embeds, which would otherwise make the
    # output differ byte-for-byte between runs even with identical inputs.
    optipng -o7 -quiet "$f"
    exiftool -all= -overwrite_original -quiet "$f"
done

echo "wrote $master (${master_size}x${master_size}, glyph ${content_size}x${content_size})"
echo "wrote $foreground (${master_size}x${master_size}, glyph ${fg_content_size}x${fg_content_size})"

cd "$repo_root"
dart run flutter_launcher_icons
