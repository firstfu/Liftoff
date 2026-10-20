#!/bin/zsh
# appcast.sh：把打包好的 Liftoff.zip 加進 Sparkle 更新清單 site/appcast.xml（App 內更新讀的就是它）
#
# 用法：scripts/appcast.sh [zip 路徑] [下載網址] [appcast 路徑]
#   zip      預設 dist/Liftoff.zip（scripts/package.sh release 的產出）
#   下載網址  預設 https://github.com/firstfu/Liftoff/releases/download/v<版本>/Liftoff.zip，
#            所以 GitHub Release 的 tag 必須是 v<版本>、資產名必須是 Liftoff.zip
#   appcast  預設 site/appcast.xml（push 到 main 後由 GitHub Pages 發佈）
#
# EdDSA 私鑰在 ~/.config/liftoff-signing/sparkle-ed25519.key（優先使用），也存在登入鑰匙圈（account「liftoff」）；
# 換電腦時 generate_keys --account liftoff -f <備份檔> 匯回。私鑰遺失＝舊版 App 再也收不到更新。
# 版本號、最低系統版本直接讀 zip 裡的 Info.plist，不靠手打，避免清單與實際 App 不一致。
set -euo pipefail
cd "$(dirname "$0")/.."
ZIP=${1:-dist/Liftoff.zip}
APPCAST=${3:-site/appcast.xml}
BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin
[[ -x $BIN/sign_update ]] || { echo "找不到 $BIN/sign_update，先建置一次專案（SPM 會下載 Sparkle）"; exit 1; }
[[ -f $ZIP ]] || { echo "找不到 $ZIP"; exit 1; }

plist=$(mktemp)
trap 'rm -f $plist' EXIT
unzip -p "$ZIP" Liftoff.app/Contents/Info.plist > $plist
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" $plist; }
VERSION=$(read_key CFBundleShortVersionString)
BUILD=$(read_key CFBundleVersion)
MIN_OS=$(read_key LSMinimumSystemVersion)
URL=${2:-https://github.com/firstfu/Liftoff/releases/download/v$VERSION/Liftoff.zip}

if [[ -f $APPCAST ]] && grep -q "<sparkle:version>$BUILD</sparkle:version>" $APPCAST; then
  echo "appcast 已有 build $BUILD，不重複加入"; exit 1
fi
# 輸出形如 sparkle:edSignature="…" length="…"。有備份金鑰檔就直接用（不跳鑰匙圈授權對話框），否則讀鑰匙圈
KEY_FILE=${SPARKLE_KEY_FILE:-$HOME/.config/liftoff-signing/sparkle-ed25519.key}
if [[ -f $KEY_FILE ]]; then
  SIGNATURE=$($BIN/sign_update --ed-key-file "$KEY_FILE" "$ZIP")
else
  SIGNATURE=$($BIN/sign_update --account liftoff "$ZIP")
fi

ITEM="    <item>
      <title>$VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/firstfu/Liftoff/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <enclosure url=\"$URL\" type=\"application/octet-stream\" $SIGNATURE />
    </item>"

if [[ ! -f $APPCAST ]]; then
  cat > $APPCAST <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Liftoff</title>
    <!-- 由 scripts/appcast.sh 產生，新版本加在最上面 -->
  </channel>
</rss>
EOF
fi
# 新項目插在 channel 的說明註解之後（最新在最上面；Sparkle 依 sparkle:version 比較，順序不影響正確性）
python3 -I - "$APPCAST" "$ITEM" <<'EOF'
import sys
path, item = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
marker = "<!-- 由 scripts/appcast.sh 產生，新版本加在最上面 -->\n"
assert marker in text, "appcast 缺少插入標記"
open(path, "w", encoding="utf-8").write(text.replace(marker, marker + item + "\n", 1))
EOF
echo "已把 $VERSION ($BUILD) 加進 $APPCAST，下載網址 $URL"
