#!/bin/zsh
# make_icon.sh：產生 1024px 母圖後縮成 AppIcon.appiconset 需要的各尺寸
set -euo pipefail
cd "$(dirname "$0")/.."
SET=Liftoff/Resources/Assets.xcassets/AppIcon.appiconset
TMP=$(mktemp -d)
swift scripts/make_icon.swift "$TMP/icon_1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
echo "已更新 $SET"
