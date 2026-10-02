# Liftoff

**A Launchpad replacement for macOS 26+ — with live window previews of running apps.**

macOS 26 的經典「啟動台」替代品：格線、資料夾、搜尋、翻頁都在，另外加上「執行中 App 的視窗縮圖預覽」。（中文說明在下方）

> **Free and open source (GPLv3).** Every line of code is here — read it, build it yourself, or check what the permissions are used for.
>
> **Solo project.** I build this on my own — please open an [Issue](../../issues/new/choose) with bugs or ideas.

## Features

- Classic Launchpad grid with pages, folders, drag to reorder, search-as-you-type
- Open with a hotkey (⌃⌘L by default), a trackpad thumb-and-three-finger pinch, a hot corner, or `open liftoff://toggle`
- Import your existing Launchpad layout
- Hover an app (or press Space on it) to preview its running windows; click a thumbnail to switch
- Search also matches the titles of open windows (including minimized and other-desktop ones) — pick one to jump straight to it
- Drag an app to the Dock to add it there
- Background: blurred wallpaper (lowest power), live blur, or your own image; adjustable icon size, label size and colors
- Multi-display aware; hide apps, uninstall apps, back up and restore your layout

## Performance (self-measured)

Opening the panel < 3 ms, < 8 ms per keystroke in search, zero dropped frames while paging, 0% CPU when idle.
`scripts/selftest.sh` reproduces the numbers on your own Mac.

## Privacy

Liftoff makes **no network connections at all**. Window thumbnails are captured and shown locally and never leave your Mac.
Don't take my word for it: the code that uses each permission is in [`Liftoff/Preview`](Liftoff/Preview) (Screen Recording: thumbnails; Accessibility: listing and switching windows) and [`Liftoff/Services`](Liftoff/Services) (hotkey, hot corner, trackpad gesture).

### A note on private APIs

Two features use undocumented macOS APIs, both loaded dynamically with a fallback — if the symbols disappear the feature turns itself off instead of crashing:

- [`Liftoff/Preview/PrivateAPI.swift`](Liftoff/Preview/PrivateAPI.swift) — SkyLight / HIServices, for window enumeration and switching (the same approach as AltTab, Hammerspoon)
- [`Liftoff/Services/TrackpadGesture.swift`](Liftoff/Services/TrackpadGesture.swift) — MultitouchSupport, for the pinch gesture (the same approach as BetterTouchTool, MiddleClick)

## Requirements

macOS 26 or later.

## Install

1. Download `Liftoff.zip` from [Releases](../../releases/latest) and unzip it.
2. Move `Liftoff.app` to `/Applications`.
3. Open it. macOS will block it the first time, because it isn't notarized by Apple yet:
   - Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to *"Liftoff" was blocked to protect your Mac.*
4. Grant the permissions it asks for: **Accessibility** (list and switch windows) and **Screen Recording** (window thumbnails, local only).

## Build from source

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/firstfu/Liftoff.git && cd Liftoff
xcodegen generate
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Liftoff.app
```

No Apple account needed — builds are ad-hoc signed by default. To sign with your own certificate (so macOS keeps the Accessibility / Screen Recording permissions across rebuilds), see [`Config/Signing.xcconfig`](Config/Signing.xcconfig).
Tests: replace `build` with `test` in the `xcodebuild` command. `scripts/install.sh` builds Release, installs to `/Applications` and registers launch at login.

## License

[GPLv3](LICENSE). You're free to use, study, modify and share it; modified versions you distribute must stay open source under the same license.

---

## 中文說明

**免費、開源（GPLv3）。**所有程式碼都在這裡，可以自己看、自己建置，確認權限拿來做什麼。這是我一個人開發的小工具，有問題或想要的功能，請開 [Issue](../../issues/new/choose) 告訴我。

### 功能

- 經典啟動台：格線、分頁、資料夾、拖曳排序、輸入即搜尋
- 快速鍵（預設 ⌃⌘L）、觸控板拇指＋三指捏合、熱角、`open liftoff://toggle` 都能開啟
- 可匯入既有的啟動台排列
- 游標停在執行中的 App 上（或按空白鍵）預覽它的視窗縮圖，點縮圖直接切換
- 搜尋也比對已開啟視窗的標題（含最小化、其他桌面的視窗），選了直接跳到那個視窗
- 把 App 拖到 Dock 即可加入 Dock
- 背景可選模糊桌布（最省電）、即時模糊、自選圖片；圖示與字級大小、顏色可調
- 支援多螢幕；可隱藏／解除安裝 App、備份與還原排列

### 隱私

Liftoff **完全不連網**。縮圖只在你的 Mac 上擷取與顯示，不會上傳。用到各權限的程式碼在 [`Liftoff/Preview`](Liftoff/Preview) 與 [`Liftoff/Services`](Liftoff/Services)，也可以用 Little Snitch、LuLu 等防火牆確認。

### 私有 API 說明

視窗列舉／切換（SkyLight、HIServices）與捏合手勢（MultitouchSupport）用到未公開的 macOS API，皆以動態載入並有 fallback：符號消失時該功能自動停用，不會 crash。

### 安裝

1. 從 [Releases](../../releases/latest) 下載 `Liftoff.zip` 並解壓縮
2. 把 `Liftoff.app` 拖進「應用程式」資料夾
3. 打開它。第一次會被系統擋下（還沒經過 Apple 公證）：
   到 **系統設定 → 隱私權與安全性**，往下捲，找到「已阻擋『Liftoff』以保護你的Mac。」這行，按旁邊的 **強制打開**
4. 依提示開啟 **輔助使用**（列出與切換視窗）與 **螢幕錄製**（視窗縮圖，只在本機處理）

### 系統需求與建置

macOS 26 以上。需要 Xcode 26 與 XcodeGen，指令見上方 **Build from source**。預設 ad-hoc 簽章，不需要 Apple 帳號；想用自己的憑證請看 [`Config/Signing.xcconfig`](Config/Signing.xcconfig)。

### 授權

[GPLv3](LICENSE)。
