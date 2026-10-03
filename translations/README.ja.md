<div align="center">

<img src="../assets/icon.png" width="128" alt="Liftoff のアイコン">

# Liftoff

**macOS 26 で消えた Launchpad を、より速く、ウインドウのライブプレビュー付きで取り戻す。**

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](../LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
[![Latest release](https://img.shields.io/github/v/release/firstfu/Liftoff)](https://github.com/firstfu/Liftoff/releases/latest)
![Languages](https://img.shields.io/badge/languages-13-brightgreen)

[ダウンロード](https://github.com/firstfu/Liftoff/releases/latest)

[English](../README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · **日本語** · [한국어](README.ko.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md)

<img src="../assets/hero.gif" width="860" alt="Liftoff の動作：開く、検索する、ウインドウをプレビューする、フォルダを開く">

</div>

## Liftoff とは

macOS 26 では、おなじみの Launchpad のグリッドが「App」リストに置き換えられました。ページ、フォルダ、ドラッグでの並べ替え、入力して検索——あのグリッドが好きだった方のために、Liftoff は macOS 26 向けにゼロから作り直し、厳しい性能基準を課しました。表示まで 3 ms 未満、ページ送りでコマ落ちなし、待機中の CPU 使用率は 0% です。

そのうえで、本家にはなかった機能を加えています。

<img src="../assets/localized/grid.ja.jpg" width="860" alt="スマート整理後の Liftoff のグリッド：開発ツール、オフィスと書類、メディア、ユーティリティなどのフォルダ">

## 機能

### ウインドウのライブプレビュー

実行中の App にポインタを重ねる（または選択して <kbd>Space</kbd> を押す）と、その App のウインドウがサムネールで表示されます。クリックすればそのウインドウへ直接移動でき、最小化したウインドウや別のデスクトップにあるウインドウも対象です。

<img src="../assets/window-preview.jpg" width="780" alt="実行中の App にポインタを重ねると、そのウインドウのサムネールが表示される">

### App もウインドウも見つかる検索

数文字入力するだけです。Liftoff は App 名、頭文字（`vsc` → Visual Studio Code）、中国語名のピンイン、そして開いているウインドウのタイトルに一致させます。

<img src="../assets/search.jpg" width="780" alt="検索フィールドに入力すると、App とウインドウが絞り込まれる">

### スマート整理

ワンクリックで、すべての App を開発ツール、書類とオフィス、メディア、ユーティリティなどの分かりやすいフォルダに仕分けします。最初に全体のプレビューが表示され、「適用」を押すまでは何も変わりません。現在の配置は自動でバックアップされます。

仕分けは推測ではなく、1,000 以上の人気 Mac App（中国、日本、韓国、台湾で人気の App を含む）を収録した内蔵の対応表にもとづきます。AI もネットワークも使わず、結果は毎回同じです。載っていない App は [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) に 1 行足すだけ。プルリクエストをお待ちしています。

<img src="../assets/localized/smart-organize.ja.png" width="780" alt="適用前に、フォルダと App の振り分けを一覧で確認できるスマート整理のプレビュー">

### そのほかの機能

- グリッドから **App を Dock へドラッグ**できます。パネルは自動的に脇へ引っ込みます
- **以前の Launchpad の配置を読み込む**ことも、スマート整理でゼロから始めることもできます
- 好きな方法で開けます：ホットキー（デフォルトは <kbd>⌃⌘L</kbd>）、親指と 3 本指のピンチ、ホットコーナー、Dock のアイコン、`open liftoff://toggle`
- ページ、フォルダ（ドラッグで統合）、ドラッグでの並べ替え、キーボード操作
- ぼかし壁紙（最も省電力）、ライブぼかし、お好みの画像から背景を選べ、アイコンサイズ、ラベルサイズ、色も調整できます
- マルチディスプレイ対応 · App を非表示 · 関連ファイルごと App をアンインストール · 配置のバックアップと復元
- 13 言語に対応し、システムの言語に合わせて表示

<img src="../assets/folder.jpg" width="780" alt="開いたフォルダ">

## パフォーマンス

アプリ自身が実機で計測した値です（`scripts/selftest.sh` を実行すれば、お使いの Mac で同じ数値を再現できます）。

| | |
|---|---|
| パネルを開く | **< 3 ms** |
| 検索（1 キーストロークあたり） | **< 8 ms** |
| ページ送り | **コマ落ち 0** |
| 待機中 | **CPU 0%** |

## プライバシー

Liftoff は**ネットワーク接続を一切行いません**。ウインドウのサムネールはローカルで取得・表示され、Mac の外へ出ることはありません。
言葉だけで信じていただく必要はありません。各権限を使うコードは [`Liftoff/Preview`](../Liftoff/Preview)（画面収録：サムネール、アクセシビリティ：ウインドウの一覧取得と切り替え）と [`Liftoff/Services`](../Liftoff/Services)（ホットキー、ホットコーナー、トラックパッドのジェスチャ）にあります。Little Snitch や LuLu でも確認できます。

### 非公開 API について

2 つの機能は、ドキュメント化されていない macOS の API を使っています。どちらも動的に読み込み、フォールバックを備えています。シンボルが消えてもクラッシュせず、その機能だけが自動的にオフになります。

- [`Liftoff/Preview/PrivateAPI.swift`](../Liftoff/Preview/PrivateAPI.swift) — SkyLight / HIServices。ウインドウの列挙と切り替えに使用（AltTab や Hammerspoon と同じ方法）
- [`Liftoff/Services/TrackpadGesture.swift`](../Liftoff/Services/TrackpadGesture.swift) — MultitouchSupport。ピンチジェスチャに使用（BetterTouchTool や MiddleClick と同じ方法）

## インストール

**macOS 26 以降**が必要です。

1. [Releases](https://github.com/firstfu/Liftoff/releases/latest) から `Liftoff.zip` をダウンロードして展開します。
2. `Liftoff.app` を `/Applications` に移動します。
3. 開きます。Apple の公証をまだ受けていないため、初回は macOS にブロックされます。**システム設定 → プライバシーとセキュリティ**を開き、下へスクロールして、*お使いのMacを保護するために“Liftoff”がブロックされました。*の横にある**このまま開く**をクリックしてください。
4. 求められる権限を許可します：**アクセシビリティ**（ウインドウの一覧取得と切り替え）と**画面収録とシステムオーディオ録音**（ウインドウのサムネール。ローカルのみ）。

> ビルドは ad-hoc 署名のため、アップデートのたびに、アクセシビリティと画面収録の許可を再度有効にするよう macOS から求められます。

## 対応言語

Liftoff はシステムの言語に合わせて表示します：English、繁體中文、简体中文、日本語、한국어、Deutsch、Français、Español、Português (Brasil)、Italiano、Русский、Türkçe、Nederlands。これ以外の言語では English で表示されます。

不自然な翻訳を見つけた、あるいは言語を追加したい場合は、インターフェースの文言がすべて 1 つのファイル [`Liftoff/Resources/Localizable.xcstrings`](../Liftoff/Resources/Localizable.xcstrings) にまとまっています。Xcode で開くか、プルリクエストを送ってください。

## ソースからビルド

Xcode 26 と [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）が必要です。

```sh
git clone https://github.com/firstfu/Liftoff.git && cd Liftoff
xcodegen generate
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Liftoff.app
```

Apple アカウントは不要で、ビルドはデフォルトで ad-hoc 署名されます。ご自身の証明書で署名する場合（再ビルドしてもアクセシビリティと画面収録の権限が保持されます）は、[`Config/Signing.xcconfig`](../Config/Signing.xcconfig) を参照してください。
テストは、`xcodebuild` コマンドの `build` を `test` に置き換えて実行します。`scripts/install.sh` は Release をビルドして `/Applications` にインストールし、ログイン時の起動を登録します。

## コントリビュート

無料のオープンソースで、開発者は 1 人です。[Issue](https://github.com/firstfu/Liftoff/issues/new/choose) もプルリクエストも大歓迎です。手軽な貢献方法は、翻訳の修正、載っていない App の [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) への追加、macOS のバージョンを添えたバグ報告です。

## ライセンス

[GPLv3](../LICENSE)。自由に使用、研究、改変、共有できます。改変版を配布する場合は、同じライセンスでオープンソースのままにする必要があります。
