<div align="center">

<img src="../assets/icon.png" width="128" alt="Liftoff 圖示">

# Liftoff

**macOS 26 拿掉的啟動台，現在回來了：更快，還多了即時視窗預覽。**

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](../LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
[![Latest release](https://img.shields.io/github/v/release/firstfu/Liftoff)](https://github.com/firstfu/Liftoff/releases/latest)
![Languages](https://img.shields.io/badge/languages-13-brightgreen)

[下載](https://github.com/firstfu/Liftoff/releases/latest)

[English](../README.md) · **繁體中文** · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md)

<img src="../assets/hero.gif" width="860" alt="Liftoff 實際操作：開啟、搜尋、預覽視窗、打開資料夾">

</div>

## 為什麼要做 Liftoff

macOS 26 把經典的啟動台格線換成了「App」清單。如果你和我一樣習慣那個格線：分頁、資料夾、拖曳排列、打字即搜尋，Liftoff 就是為你做的。它專為 macOS 26 從頭打造，並嚴守效能底線：開啟不到 3 ms、翻頁絕不掉幀、閒置時 CPU 使用率 0%。

然後，它再加上原版從來沒有的功能。

<img src="../assets/localized/grid.zh-Hant.jpg" width="860" alt="Liftoff 在「智慧整理」之後的格線：開發工具、辦公與文件、媒體、工具程式等資料夾">

## 功能

### 即時視窗預覽

把游標停在執行中的 App 上（或對它按<kbd>空白鍵</kbd>），它的視窗就會以縮圖顯示。點一下縮圖，直接切到那個視窗，最小化的視窗和其他桌面上的視窗也行。

<img src="../assets/window-preview.jpg" width="780" alt="游標停在執行中的 App 上，顯示它的視窗縮圖">

### App 和視窗一次找齊的搜尋

打幾個字就好。Liftoff 會比對 App 名稱、縮寫（`vsc` → Visual Studio Code）、中文名稱的拼音，以及你已開啟視窗的標題。

<img src="../assets/search.jpg" width="780" alt="在搜尋欄輸入文字，即時篩選 App 與視窗">

### 智慧整理

一鍵把你所有的 App 分進合理的資料夾：開發工具、文件與辦公、媒體、工具程式……套用前會先給你完整預覽，按下「套用」之前什麼都不會變，目前的排列也會自動備份。

它靠的是內建、收錄 1,000 多款熱門 Mac App 的對照表（包含在中國、日本、韓國與台灣常用的 App），不是靠猜：沒有 AI、不連網，每次結果都一樣。少了哪個 App？在 [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) 加一行就好，歡迎發 pull request。

<img src="../assets/localized/smart-organize.zh-Hant.png" width="780" alt="智慧整理預覽：套用前先列出各資料夾與其中的 App">

### 還有更多

- **直接從格線把 App 拖進 Dock**，啟動台會自動讓開
- **匯入舊的啟動台排列**，或用智慧整理重新開始
- 開啟方式隨你挑：快速鍵（預設 <kbd>⌃⌘L</kbd>）、拇指加三指捏合、熱點、Dock 圖示，或 `open liftoff://toggle`
- 分頁、資料夾（拖曳合併）、拖曳排序、鍵盤操作
- 模糊桌布（最省電）、即時模糊或自選圖片；圖示大小、標籤大小與顏色都能調整
- 支援多螢幕 · 可隱藏 App · 解除安裝 App 並清除殘留檔案 · 備份與還原排列
- 支援 13 種語言，跟隨系統語言

<img src="../assets/folder.jpg" width="780" alt="打開的資料夾">

## 效能

由 App 自己在真實的 Mac 上量測（在你的 Mac 上執行 `scripts/selftest.sh` 即可重現這些數字）：

| | |
|---|---|
| 開啟面板 | **< 3 ms** |
| 搜尋，每次按鍵 | **< 8 ms** |
| 翻頁 | **0 掉幀** |
| 閒置 | **0% CPU** |

## 隱私

Liftoff **完全不連網**。視窗縮圖只在你的 Mac 上擷取與顯示，不會離開你的電腦。
不必只聽我說：用到各項權限的程式碼都在這裡，[`Liftoff/Preview`](../Liftoff/Preview)（螢幕與系統錄音：縮圖；輔助使用：列出與切換視窗）和 [`Liftoff/Services`](../Liftoff/Services)（快速鍵、熱點、觸控式軌跡板手勢）。用 Little Snitch 或 LuLu 也能確認。

### 關於私有 API

有兩項功能用到未公開的 macOS API，都是動態載入並附有 fallback：如果這些符號消失，該功能會自動關閉，而不是當掉。

- [`Liftoff/Preview/PrivateAPI.swift`](../Liftoff/Preview/PrivateAPI.swift)：SkyLight / HIServices，用於列舉與切換視窗（做法與 AltTab、Hammerspoon 相同）
- [`Liftoff/Services/TrackpadGesture.swift`](../Liftoff/Services/TrackpadGesture.swift)：MultitouchSupport，用於捏合手勢（做法與 BetterTouchTool、MiddleClick 相同）

## 安裝

需要 **macOS 26 或以上版本**。

1. 從 [Releases](https://github.com/firstfu/Liftoff/releases/latest) 下載 `Liftoff.zip` 並解壓縮。
2. 把 `Liftoff.app` 移到 `/Applications`。
3. 打開它。第一次開啟時 macOS 會擋下，因為它還沒有經過 Apple 公證：請打開 **系統設定 → 隱私權與安全性**，往下捲動，在「已阻擋「Liftoff」以保護你的Mac。」旁邊按下 **強制打開**。
4. 依提示授予權限：**輔助使用**（列出與切換視窗）和 **螢幕與系統錄音**（視窗縮圖，只在本機處理）。

> 這些建置版本採用 ad-hoc 簽章，因此每次更新後，macOS 都會要求你重新開啟輔助使用與螢幕與系統錄音的權限。

## 語言

Liftoff 跟隨系統語言：English、繁體中文、简体中文、日本語、한국어、Deutsch、Français、Español、Português (Brasil)、Italiano、Русский、Türkçe 和 Nederlands。其他語言會改用英文。

發現不通順的翻譯，或想新增語言？所有介面文字都在同一個檔案 [`Liftoff/Resources/Localizable.xcstrings`](../Liftoff/Resources/Localizable.xcstrings)，用 Xcode 打開就能改，也歡迎發 pull request。

## 從原始碼建置

需要 Xcode 26 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```sh
git clone https://github.com/firstfu/Liftoff.git && cd Liftoff
xcodegen generate
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Liftoff.app
```

不需要 Apple 帳號，預設為 ad-hoc 簽章。若要用自己的憑證簽署（讓 macOS 在重新建置後仍保留輔助使用與螢幕與系統錄音的權限），請參閱 [`Config/Signing.xcconfig`](../Config/Signing.xcconfig)。
測試：把 `xcodebuild` 指令中的 `build` 換成 `test`。`scripts/install.sh` 會建置 Release、安裝到 `/Applications` 並設定開機自動啟動。

## 參與貢獻

免費、開源，由一個人開發，非常歡迎 [issue](https://github.com/firstfu/Liftoff/issues/new/choose) 與 pull request。最容易幫上忙的方式：修正翻譯、把缺少的 App 補進 [`AppCategories.json`](../Liftoff/Resources/AppCategories.json)，或回報 bug 時附上你的 macOS 版本。

## 授權

[GPLv3](../LICENSE)。你可以自由使用、研究、修改與分享；你散布的修改版本必須以相同授權保持開源。
