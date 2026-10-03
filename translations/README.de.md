<div align="center">

<img src="../assets/icon.png" width="128" alt="Liftoff-Symbol">

# Liftoff

**Das Launchpad, das macOS 26 gestrichen hat – zurück, schneller und mit Live-Fenstervorschau.**

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](../LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
[![Latest release](https://img.shields.io/github/v/release/firstfu/Liftoff)](https://github.com/firstfu/Liftoff/releases/latest)
![Languages](https://img.shields.io/badge/languages-13-brightgreen)

[Download](https://github.com/firstfu/Liftoff/releases/latest)

[English](../README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · **Deutsch** · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md)

<img src="../assets/hero.gif" width="860" alt="Liftoff in Aktion: öffnen, suchen, Fenster in der Vorschau ansehen, einen Ordner öffnen">

</div>

## Warum Liftoff

Mit macOS 26 ist das klassische Launchpad-Raster der „Apps“-Liste gewichen. Wenn du das Raster mochtest – Seiten, Ordner, Umsortieren per Drag-and-drop, Tippen zum Suchen –, bringt Liftoff es zurück. Von Grund auf für macOS 26 gebaut und an harten Performance-Grenzen gemessen: Es öffnet sich in unter 3 ms, lässt beim Blättern keinen einzigen Frame fallen und braucht im Leerlauf 0 % CPU.

Und dann kommt dazu, was das Original nie konnte.

<img src="../assets/localized/grid.de.jpg" width="860" alt="Das Raster von Liftoff nach „Intelligent organisieren“: Ordner für Entwickler-Werkzeuge, Büro & Dokumente, Medien, Dienstprogramme und mehr">

## Funktionen

### Live-Fenstervorschau

Lass den Zeiger auf einer laufenden App ruhen (oder drücke darauf die <kbd>Leertaste</kbd>), und ihre Fenster erscheinen als Miniaturen. Ein Klick auf eine Miniatur springt direkt zu diesem Fenster – auch bei minimierten Fenstern und Fenstern auf anderen Schreibtischen.

<img src="../assets/window-preview.jpg" width="780" alt="Beim Darüberfahren mit dem Zeiger zeigt eine laufende App Miniaturen ihrer Fenster">

### Eine Suche, die Apps *und* Fenster findet

Tipp ein paar Buchstaben. Liftoff findet App-Namen, Initialen (`vsc` → Visual Studio Code), Pinyin bei chinesischen Namen und die Titel deiner geöffneten Fenster.

<img src="../assets/search.jpg" width="780" alt="Die Eingabe im Suchfeld filtert Apps und Fenster">

### Intelligent organisieren

Ein Klick sortiert deine gesamte App-Sammlung in sinnvolle Ordner – Entwickler-Werkzeuge, Büro & Dokumente, Medien, Dienstprogramme … Vorher siehst du eine vollständige Vorschau, nichts ändert sich, bevor du auf „Anwenden“ klickst, und deine aktuelle Anordnung wird automatisch gesichert.

Grundlage ist eine eingebaute Tabelle mit über 1.000 beliebten Mac-Apps (darunter auch in China, Japan, Korea und Taiwan beliebte Apps) – keine Vermutungen: keine KI, kein Netzwerk, jedes Mal dasselbe Ergebnis. Fehlt eine App? Dann reicht eine Zeile in [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) – Pull Requests sind willkommen.

<img src="../assets/localized/smart-organize.de.png" width="780" alt="Vorschau von „Intelligent organisieren“ mit den Ordnern und Apps, bevor du sie anwendest">

### Und noch mehr

- **App ins Dock ziehen**, direkt aus dem Raster – das Fenster macht dabei automatisch Platz
- **Alte Launchpad-Anordnung importieren** oder mit „Intelligent organisieren“ ganz neu starten
- Öffne es, wie du willst: Tastenkurzbefehl (standardmäßig <kbd>⌃⌘L</kbd>), Zusammenziehen mit Daumen und drei Fingern, eine aktive Ecke, das Dock-Symbol oder `open liftoff://toggle`
- Seiten, Ordner (zum Zusammenführen ziehen), Umsortieren per Drag-and-drop, Tastaturnavigation
- Unscharfes Hintergrundbild (am sparsamsten), Live-Unschärfe oder ein eigenes Bild; Symbolgröße, Beschriftungsgröße und Farben einstellbar
- Mehrere Displays werden unterstützt · Apps ausblenden · Apps samt Restdateien deinstallieren · Anordnung sichern und wiederherstellen
- 13 Sprachen, passend zur Systemsprache

<img src="../assets/folder.jpg" width="780" alt="Ein geöffneter Ordner">

## Performance

Von der App selbst auf einem echten Mac gemessen (mit `scripts/selftest.sh` kannst du die Zahlen auf deinem Mac nachmessen):

| | |
|---|---|
| Fenster öffnen | **< 3 ms** |
| Suche, pro Tastenanschlag | **< 8 ms** |
| Blättern | **0 verlorene Frames** |
| Leerlauf | **0 % CPU** |

## Datenschutz

Liftoff baut **überhaupt keine Netzwerkverbindungen** auf. Fensterminiaturen werden lokal aufgenommen und angezeigt und verlassen deinen Mac nie.
Du musst mir das nicht einfach glauben: Der Code, der die jeweilige Berechtigung nutzt, liegt in [`Liftoff/Preview`](../Liftoff/Preview) (Aufnahme von Bildschirm & Systemaudio: Miniaturen; Bedienungshilfen: Fenster auflisten und wechseln) und [`Liftoff/Services`](../Liftoff/Services) (Tastenkurzbefehl, aktive Ecke, Trackpad-Geste). Auch Little Snitch oder LuLu bestätigen es dir.

### Hinweis zu privaten APIs

Zwei Funktionen nutzen undokumentierte macOS-APIs. Beide werden dynamisch geladen und haben einen Fallback – verschwinden die Symbole, schaltet sich die Funktion von selbst ab, statt abzustürzen:

- [`Liftoff/Preview/PrivateAPI.swift`](../Liftoff/Preview/PrivateAPI.swift) – SkyLight / HIServices zum Auflisten und Wechseln von Fenstern (derselbe Ansatz wie bei AltTab und Hammerspoon)
- [`Liftoff/Services/TrackpadGesture.swift`](../Liftoff/Services/TrackpadGesture.swift) – MultitouchSupport für die Zusammenziehen-Geste (derselbe Ansatz wie bei BetterTouchTool und MiddleClick)

## Installation

Erfordert **macOS 26 oder neuer**.

1. Lade `Liftoff.zip` von den [Releases](https://github.com/firstfu/Liftoff/releases/latest) herunter und entpacke es.
2. Verschiebe `Liftoff.app` nach `/Applications`.
3. Öffne die App. macOS blockiert sie beim ersten Mal, weil sie noch nicht von Apple notarisiert ist: Öffne **Systemeinstellungen → Datenschutz & Sicherheit**, scrolle nach unten und klicke bei *„Liftoff“ wurde blockiert, um deinen Mac zu schützen.* auf **Dennoch öffnen**.
4. Erteile die Berechtigungen, nach denen die App fragt: **Bedienungshilfen** (Fenster auflisten und wechseln) und **Aufnahme von Bildschirm & Systemaudio** (Fensterminiaturen, nur lokal).

> Die Builds sind ad-hoc signiert, deshalb fragt macOS nach jedem Update erneut, ob du Bedienungshilfen und Aufnahme von Bildschirm & Systemaudio wieder aktivieren willst.

## Sprachen

Liftoff folgt deiner Systemsprache: English, 繁體中文, 简体中文, 日本語, 한국어, Deutsch, Français, Español, Português (Brasil), Italiano, Русский, Türkçe und Nederlands. Alles andere fällt auf Englisch zurück.

Dir ist eine holprige Übersetzung aufgefallen, oder du möchtest eine Sprache hinzufügen? Der gesamte Oberflächentext steckt in einer einzigen Datei, [`Liftoff/Resources/Localizable.xcstrings`](../Liftoff/Resources/Localizable.xcstrings) – öffne sie in Xcode oder schick einen Pull Request.

## Aus dem Quellcode bauen

Erfordert Xcode 26 und [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/firstfu/Liftoff.git && cd Liftoff
xcodegen generate
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Liftoff.app
```

Du brauchst keinen Apple-Account – Builds sind standardmäßig ad-hoc signiert. Wenn du mit deinem eigenen Zertifikat signieren willst (damit macOS die Berechtigungen für Bedienungshilfen und Aufnahme von Bildschirm & Systemaudio über Neubuilds hinweg behält), schau in [`Config/Signing.xcconfig`](../Config/Signing.xcconfig).
Tests: Ersetze im `xcodebuild`-Befehl `build` durch `test`. `scripts/install.sh` baut Release, installiert nach `/Applications` und richtet den Start bei der Anmeldung ein.

## Mitmachen

Kostenlos und Open Source, von einer einzelnen Person gebaut – [Issues](https://github.com/firstfu/Liftoff/issues/new/choose) und Pull Requests sind herzlich willkommen. Am einfachsten hilfst du so: eine Übersetzung korrigieren, eine fehlende App in [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) ergänzen oder einen Bug samt deiner macOS-Version melden.

## Lizenz

[GPLv3](../LICENSE). Du darfst es frei nutzen, untersuchen, verändern und weitergeben; veränderte Versionen, die du verbreitest, müssen unter derselben Lizenz Open Source bleiben.
