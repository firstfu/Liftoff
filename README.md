<div align="center">

<img src="assets/icon.png" width="128" alt="Liftoff icon">

# Liftoff

**The Launchpad that macOS 26 took away — back, faster, and with live window previews.**

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
[![Latest release](https://img.shields.io/github/v/release/firstfu/Liftoff)](https://github.com/firstfu/Liftoff/releases/latest)
![Languages](https://img.shields.io/badge/languages-13-brightgreen)

[Download](https://github.com/firstfu/Liftoff/releases/latest) · [Features](#features) · [Install](#install) · [Privacy](#privacy) · [Translations](#languages)

English · [繁體中文](translations/README.zh-Hant.md) · [简体中文](translations/README.zh-Hans.md) · [日本語](translations/README.ja.md) · [한국어](translations/README.ko.md) · [Deutsch](translations/README.de.md) · [Français](translations/README.fr.md) · [Español](translations/README.es.md) · [Português](translations/README.pt-BR.md) · [Italiano](translations/README.it.md) · [Русский](translations/README.ru.md) · [Türkçe](translations/README.tr.md) · [Nederlands](translations/README.nl.md)

<img src="assets/hero.gif" width="860" alt="Liftoff in action: open, search, preview windows, open a folder">

</div>

## Why Liftoff

macOS 26 replaced the classic Launchpad grid with the "Apps" list. If you liked the grid — pages, folders, drag to rearrange, type to search — Liftoff gives it back, built from scratch for macOS 26 and held to hard performance limits: it opens in under 3 ms, never drops a frame while paging, and uses 0% CPU when idle.

Then it adds what the original never had.

<img src="assets/grid.jpg" width="860" alt="Liftoff's grid after Smart Organize: folders for Developer Tools, Office & Documents, Media, Utilities and more">

## Features

### Live window previews

Rest the pointer on a running app (or press <kbd>Space</kbd> on it) and its windows appear as thumbnails. Click one to jump straight to that window — minimized windows and windows on other desktops included.

<img src="assets/window-preview.jpg" width="780" alt="Hovering a running app shows thumbnails of its windows">

### Search that finds apps *and* windows

Type a few letters. Liftoff matches app names, initials (`vsc` → Visual Studio Code), pinyin for Chinese names, and the titles of your open windows.

<img src="assets/search.jpg" width="780" alt="Typing in the search field filters apps and windows">

### Smart Organize

One click sorts your whole app collection into sensible folders — Developer Tools, Documents & Office, Media, Utilities… You see a full preview first, nothing changes until you press Apply, and your current layout is backed up automatically.

It works from a built-in table of 1,000+ popular Mac apps (including apps popular in China, Japan, Korea and Taiwan), not from guesses: no AI, no network, the same result every time. Missing an app? It's one line in [`AppCategories.json`](Liftoff/Resources/AppCategories.json) — pull requests welcome.

<img src="assets/smart-organize.png" width="780" alt="Smart Organize preview listing the folders and apps before applying">

### And more

- **Drag an app to the Dock** straight from the grid — the panel gets out of the way automatically
- **Import your old Launchpad layout**, or start fresh with Smart Organize
- Open it any way you like: hotkey (<kbd>⌃⌘L</kbd> by default), thumb-and-three-finger pinch, a hot corner, the Dock icon, or `open liftoff://toggle`
- Pages, folders (drag to merge), drag to reorder, keyboard navigation
- Blurred wallpaper (lowest power), live blur, or your own image; adjustable icon size, label size and colors
- Multi-display aware · hide apps · uninstall apps with leftovers · back up and restore your layout
- 13 languages, following your system language

<img src="assets/folder.jpg" width="780" alt="An open folder">

## Performance

Measured on a real Mac by the app itself (`scripts/selftest.sh` reproduces the numbers on yours):

| | |
|---|---|
| Open the panel | **< 3 ms** |
| Search, per keystroke | **< 8 ms** |
| Paging | **0 dropped frames** |
| Idle | **0% CPU** |

## Privacy

Liftoff makes **no network connections at all**. Window thumbnails are captured and shown locally and never leave your Mac.
Don't take my word for it: the code that uses each permission is in [`Liftoff/Preview`](Liftoff/Preview) (Screen Recording: thumbnails; Accessibility: listing and switching windows) and [`Liftoff/Services`](Liftoff/Services) (hotkey, hot corner, trackpad gesture). Little Snitch or LuLu will confirm it too.

### A note on private APIs

Two features use undocumented macOS APIs, both loaded dynamically with a fallback — if the symbols disappear the feature turns itself off instead of crashing:

- [`Liftoff/Preview/PrivateAPI.swift`](Liftoff/Preview/PrivateAPI.swift) — SkyLight / HIServices, for window enumeration and switching (the same approach as AltTab and Hammerspoon)
- [`Liftoff/Services/TrackpadGesture.swift`](Liftoff/Services/TrackpadGesture.swift) — MultitouchSupport, for the pinch gesture (the same approach as BetterTouchTool and MiddleClick)

## Install

Requires **macOS 26 or later**.

1. Download `Liftoff.zip` from [Releases](https://github.com/firstfu/Liftoff/releases/latest) and unzip it.
2. Move `Liftoff.app` to `/Applications`.
3. Open it. macOS will block it the first time, because it isn't notarized by Apple yet: open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to *"Liftoff" was blocked to protect your Mac.*
4. Grant the permissions it asks for: **Accessibility** (list and switch windows) and **Screen Recording** (window thumbnails, local only).

> Builds are ad-hoc signed, so macOS asks you to re-enable Accessibility and Screen Recording after each update.

## Languages

Liftoff follows your system language: English, 繁體中文, 简体中文, 日本語, 한국어, Deutsch, Français, Español, Português (Brasil), Italiano, Русский, Türkçe and Nederlands. Anything else falls back to English.

Spotted an awkward translation, or want to add a language? All interface text lives in one file, [`Liftoff/Resources/Localizable.xcstrings`](Liftoff/Resources/Localizable.xcstrings) — open it in Xcode, or send a pull request.

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

## Contributing

Free and open source, built by one person — [issues](https://github.com/firstfu/Liftoff/issues/new/choose) and pull requests are very welcome. The easiest ways to help: fix a translation, add a missing app to [`AppCategories.json`](Liftoff/Resources/AppCategories.json), or report a bug with your macOS version.

## License

[GPLv3](LICENSE). You're free to use, study, modify and share it; modified versions you distribute must stay open source under the same license.
