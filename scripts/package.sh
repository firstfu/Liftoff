#!/bin/zsh
# package.sh：建置 Release 並打包成可公開下載的 Liftoff.zip（未公證的測試版）
#
# 用法：scripts/package.sh [dev|adhoc|release]
#   dev   （預設）沿用 Config/Signing.xcconfig 的簽章（沒有 Signing.local.xcconfig 時即 ad-hoc）。
#          若用 Apple Development 憑證，更新版本後使用者的系統權限會保留，
#          但簽章裡帶有憑證持有人的姓名，任何人用 codesign 都看得到。
#   adhoc  重新以 ad-hoc 簽章，不含任何個人資訊；代價是每次更新後使用者要重新開啟
#          「輔助使用」與「螢幕錄製」權限（系統以程式碼雜湊辨識 ad-hoc 簽章的 App）。
#   release 對外發佈用。以鑰匙圈中的自簽憑證（RELEASE_IDENTITY，預設「Liftoff Release Signing」）重新簽章。
#          系統以「bundle id + 憑證雜湊」辨識 App，不隨程式碼改變，所以**更新後權限會保留**；
#          憑證只有 CN、不含姓名或 Team ID。仍未經公證，第一次開啟仍要按「仍要打開」。
#          憑證私鑰務必保留同一把：換憑證等於換身分，所有使用者都要重新授權一次。
#
# 產出：dist/Liftoff.zip 與 dist/Liftoff.zip.sha256
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=${1:-dev}
RELEASE_IDENTITY=${RELEASE_IDENTITY:-Liftoff Release Signing}
[[ $MODE == dev || $MODE == adhoc || $MODE == release ]] || { echo "用法：$0 [dev|adhoc|release]"; exit 1; }
if [[ $MODE == release ]] && ! security find-identity -p codesigning | grep -q "\"$RELEASE_IDENTITY\""; then
  echo "鑰匙圈裡找不到簽章憑證「$RELEASE_IDENTITY」"; exit 1
fi

xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build \
  -destination 'platform=macOS' build -quiet

rm -rf dist && mkdir -p dist
ditto build/Build/Products/Release/Liftoff.app dist/Liftoff.app
if [[ $MODE != dev ]]; then
  # --options runtime 保留 hardened runtime；entitlements 沿用原本的（目前為空）
  [[ $MODE == adhoc ]] && IDENTITY=- || IDENTITY=$RELEASE_IDENTITY
  codesign --force --deep --options runtime --sign "$IDENTITY" \
    --entitlements Liftoff/Resources/Liftoff.entitlements dist/Liftoff.app
fi
codesign --verify --deep --strict dist/Liftoff.app

# ditto -c -k --keepParent：保留 bundle 結構與延伸屬性，Finder 解壓縮即為 Liftoff.app
ditto -c -k --keepParent dist/Liftoff.app dist/Liftoff.zip
rm -rf dist/Liftoff.app
shasum -a 256 dist/Liftoff.zip | tee dist/Liftoff.zip.sha256
echo "簽章方式：$MODE；產出 dist/Liftoff.zip"
