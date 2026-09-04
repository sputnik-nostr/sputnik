#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
svg="$repo_root/logo.svg"
master="$repo_root/assets/icon/icon.png"
foreground="$repo_root/assets/icon/icon_foreground.png"

padding_ratio=0.88
foreground_padding_ratio=0.55
master_size=1024

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

full="$tmp/full.png"
trimmed="$tmp/trimmed.png"
rsvg-convert -w "$master_size" -h "$master_size" "$svg" -o "$full"
magick "$full" -trim +repage "$trimmed"

mkdir -p "$(dirname "$master")"

content_size="$(awk -v s="$master_size" -v r="$padding_ratio" 'BEGIN { printf "%d", s * r }')"

magick "$trimmed" -resize "${content_size}x${content_size}" \
    -background white -gravity center -extent "${master_size}x${master_size}" \
    -alpha remove -alpha off \
    "$master"

fg_content_size="$(awk -v s="$master_size" -v r="$foreground_padding_ratio" 'BEGIN { printf "%d", s * r }')"

magick "$trimmed" -resize "${fg_content_size}x${fg_content_size}" \
    -background none -gravity center -extent "${master_size}x${master_size}" \
    "$foreground"

for f in "$master" "$foreground"; do
    optipng -o7 -quiet "$f"
    exiftool -all= -overwrite_original -quiet "$f"
done

echo "wrote $master (${master_size}x${master_size}, glyph ${content_size}x${content_size})"
echo "wrote $foreground (${master_size}x${master_size}, glyph ${fg_content_size}x${fg_content_size})"

cd "$repo_root"
dart run flutter_launcher_icons
