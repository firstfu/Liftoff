<div align="center">

<img src="../assets/icon.png" width="128" alt="Liftoff 图标">

# Liftoff

**macOS 26 拿走的启动台，现在回来了：更快，还能实时预览窗口。**

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](../LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
[![Latest release](https://img.shields.io/github/v/release/firstfu/Liftoff)](https://github.com/firstfu/Liftoff/releases/latest)
![Languages](https://img.shields.io/badge/languages-13-brightgreen)

[Download](https://github.com/firstfu/Liftoff/releases/latest)

[English](../README.md) · [繁體中文](README.zh-Hant.md) · **简体中文** · [日本語](README.ja.md) · [한국어](README.ko.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md)

<img src="../assets/hero.gif" width="860" alt="Liftoff 实际效果：打开、搜索、预览窗口、打开文件夹">

</div>

## 为什么选择 Liftoff

macOS 26 用“App”列表取代了经典的启动台网格。如果你喜欢那个网格，喜欢分页、文件夹、拖动排序、打字即搜，Liftoff 就把它还给你。它专为 macOS 26 从零写成，并且守着严格的性能底线：打开不到 3 ms，翻页不掉一帧，闲置时 CPU 占用 0%。

而且，它还多了原版从来没有的东西。

<img src="../assets/localized/grid.zh-Hans.jpg" width="860" alt="智能整理之后的 Liftoff 网格：开发工具、办公与文档、媒体、实用工具等文件夹">

## 功能

### 实时窗口预览

把指针停在正在运行的 App 上（或选中后按<kbd>空格键</kbd>），它的所有窗口就会以缩略图显示。点按任意一个，即可直接跳到该窗口，最小化的窗口和其他桌面上的窗口也不例外。

<img src="../assets/window-preview.jpg" width="780" alt="悬停在运行中的 App 上，显示它的窗口缩略图">

### 同时搜索 App 和窗口

随手敲几个字母。Liftoff 会匹配 App 名称、首字母缩写（`vsc` → Visual Studio Code）、中文名称的拼音，以及你已打开窗口的标题。

<img src="../assets/search.jpg" width="780" alt="在搜索栏中输入文字，实时筛选 App 和窗口">

### 智能整理

一键把你的全部 App 归入合理的文件夹：开发工具、文档与办公、媒体、实用工具……整理前会先给你完整预览，点按“应用”之前不会有任何改动，当前的排列也会自动备份。

它依据内置的对照表分类，收录 1,000 多款常用 Mac App（包括在中国大陆、日本、韩国和台湾地区流行的 App），不靠猜测：不用 AI，不联网，每次结果都一样。少了哪个 App？在 [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) 里加一行就行，欢迎提交 pull request。

<img src="../assets/localized/smart-organize.zh-Hans.png" width="780" alt="智能整理预览：应用前先列出各个文件夹和其中的 App">

### 还有更多

- **直接从网格把 App 拖进程序坞**，面板会自动收起让路
- **导入旧的启动台排列**，或用智能整理重新开始
- 随你喜欢的方式打开：快捷键（默认 <kbd>⌃⌘L</kbd>）、拇指加三指捏合、触发角、程序坞图标，或 `open liftoff://toggle`
- 分页、文件夹（拖动即可合并）、拖动排序、键盘导航
- 模糊壁纸（最省电）、实时模糊，或你自己的图片；图标大小、标签大小和颜色都可调整
- 支持多显示器 · 隐藏 App · 卸载 App 并清理残留文件 · 备份与还原排列
- 13 种语言，跟随系统语言

<img src="../assets/folder.jpg" width="780" alt="已打开的文件夹">

## 性能

由 App 自己在真实的 Mac 上测得（`scripts/selftest.sh` 可以在你的机器上重现这些数字）：

| | |
|---|---|
| 打开面板 | **< 3 ms** |
| 搜索，每次按键 | **< 8 ms** |
| 翻页 | **0 掉帧** |
| 闲置 | **0% CPU** |

## 隐私

Liftoff **完全不建立任何网络连接**。窗口缩略图只在本机截取和显示，绝不会离开你的 Mac。
不必只听我说：每项权限对应的代码都摆在这里，见 [`Liftoff/Preview`](../Liftoff/Preview)（录屏：缩略图；无障碍：列出和切换窗口）与 [`Liftoff/Services`](../Liftoff/Services)（快捷键、触发角、触控板手势）。用 Little Snitch 或 LuLu 也能验证。

### 关于私有 API

有两项功能用到了 macOS 未公开的 API，均为动态加载并带有 fallback：如果这些符号消失，该功能会自动关闭，而不是崩溃。

- [`Liftoff/Preview/PrivateAPI.swift`](../Liftoff/Preview/PrivateAPI.swift)：SkyLight / HIServices，用于枚举和切换窗口（做法与 AltTab、Hammerspoon 相同）
- [`Liftoff/Services/TrackpadGesture.swift`](../Liftoff/Services/TrackpadGesture.swift)：MultitouchSupport，用于捏合手势（做法与 BetterTouchTool、MiddleClick 相同）

## 安装

需要 **macOS 26 或更高版本**。

1. 从 [Releases](https://github.com/firstfu/Liftoff/releases/latest) 下载 `Liftoff.zip` 并解压。
2. 把 `Liftoff.app` 移到 `/Applications`。
3. 打开它。由于尚未经过 Apple 公证，macOS 第一次会阻止它：打开 **系统设置 → 隐私与安全**，向下滚动，在*已阻止“Liftoff”以保护Mac。*旁边点按 **仍要打开**。
4. 授予它请求的权限：**无障碍**（列出和切换窗口）与 **录屏与系统录音**（窗口缩略图，仅在本机处理）。

> 安装包为 ad-hoc 签名，因此每次更新后，macOS 都会要求你重新启用“无障碍”和“录屏与系统录音”。

## 语言

Liftoff 跟随你的系统语言：English、繁體中文、简体中文、日本語、한국어、Deutsch、Français、Español、Português (Brasil)、Italiano、Русский、Türkçe 和 Nederlands。其他语言会回退到英文。

发现生硬的翻译，或想新增一种语言？所有界面文字都在同一个文件里：[`Liftoff/Resources/Localizable.xcstrings`](../Liftoff/Resources/Localizable.xcstrings)。用 Xcode 打开它，或直接提交 pull request。

## 从源码构建

需要 Xcode 26 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```sh
git clone https://github.com/firstfu/Liftoff.git && cd Liftoff
xcodegen generate
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Liftoff.app
```

不需要 Apple 账号，默认即为 ad-hoc 签名。想用自己的证书签名（这样重新构建后 macOS 仍会保留“无障碍”和“录屏与系统录音”权限），请参阅 [`Config/Signing.xcconfig`](../Config/Signing.xcconfig)。
测试：把 `xcodebuild` 命令中的 `build` 换成 `test`。`scripts/install.sh` 会构建 Release 版本，安装到 `/Applications`，并注册登录时自动启动。

## 参与贡献

免费开源，由一个人打造，非常欢迎提交 [issue](https://github.com/firstfu/Liftoff/issues/new/choose) 和 pull request。最简单的帮忙方式：修正翻译、在 [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) 里补上缺少的 App，或者附上你的 macOS 版本来报告 bug。

## 许可证

[GPLv3](../LICENSE)。你可以自由地使用、研究、修改和分享；你分发的修改版本必须沿用同一许可证继续开源。
