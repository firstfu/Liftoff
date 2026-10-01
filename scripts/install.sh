#!/bin/zsh
# install.sh：建置 Release、安裝到 /Applications、註冊開機啟動；
# 並把 build 資料夾裡的副本從 LaunchServices 移除，讓 liftoff:// 與「打開 Liftoff」都指向 /Applications 那份
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build -destination 'platform=macOS' build -quiet
pkill -x Liftoff || true
sleep 0.5
ditto build/Build/Products/Release/Liftoff.app /Applications/Liftoff.app
codesign --verify --deep --strict /Applications/Liftoff.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for copy in build/Build/Products/*/Liftoff.app(N); do
  "$LSREGISTER" -u "$PWD/$copy" >/dev/null 2>&1 || true
done
"$LSREGISTER" -f /Applications/Liftoff.app
open /Applications/Liftoff.app --args --register-login-item --background
echo "已安裝 /Applications/Liftoff.app 並設定開機啟動（快速鍵 ⌃⌘L，或點 Dock 上的圖示）"
