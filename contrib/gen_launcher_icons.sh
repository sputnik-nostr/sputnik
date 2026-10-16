#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
svg="$repo_root/assets/logo.svg"
master="$repo_root/assets/icon/icon.png"
foreground="$repo_root/assets/icon/icon_foreground.png"
round="$repo_root/assets/icon/icon_round.png"

padding_ratio=0.88
foreground_padding_ratio=0.55
round_padding_ratio=0.825
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

round_content_size="$(awk -v s="$master_size" -v r="$round_padding_ratio" 'BEGIN { printf "%d", s * r }')"
radius="$(awk -v s="$master_size" 'BEGIN { printf "%.1f", (s - 1) / 2 }')"

magick -size "${master_size}x${master_size}" xc:none -fill white \
    -draw "circle $radius,$radius $radius,0" \
    \( "$trimmed" -resize "${round_content_size}x${round_content_size}" \) \
    -gravity center -composite -depth 8 \
    "$round"

for f in "$master" "$foreground" "$round"; do
    optipng -o7 -quiet "$f"
    exiftool -all= -overwrite_original -quiet "$f"
done

echo "wrote $master (${master_size}x${master_size}, glyph ${content_size}x${content_size})"
echo "wrote $foreground (${master_size}x${master_size}, glyph ${fg_content_size}x${fg_content_size})"
echo "wrote $round (${master_size}x${master_size}, glyph ${round_content_size}x${round_content_size})"

cd "$repo_root"
dart run flutter_launcher_icons
