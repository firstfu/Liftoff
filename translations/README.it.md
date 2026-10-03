<div align="center">

<img src="../assets/icon.png" width="128" alt="Icona di Liftoff">

# Liftoff

**Il Launchpad che macOS 26 ti ha tolto: di nuovo qui, più veloce e con le anteprime delle finestre in tempo reale.**

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](../LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
[![Latest release](https://img.shields.io/github/v/release/firstfu/Liftoff)](https://github.com/firstfu/Liftoff/releases/latest)
![Languages](https://img.shields.io/badge/languages-13-brightgreen)

[Download](https://github.com/firstfu/Liftoff/releases/latest)

[English](../README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt-BR.md) · **Italiano** · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md)

<img src="../assets/hero.gif" width="860" alt="Liftoff in azione: apertura, ricerca, anteprima delle finestre, apertura di una cartella">

</div>

## Perché Liftoff

macOS 26 ha sostituito la classica griglia di Launchpad con l'elenco "App". Se la griglia ti piaceva, con le sue pagine, le cartelle, il trascinamento per riordinare e la ricerca mentre scrivi, Liftoff te la restituisce: è stato scritto da zero per macOS 26 e rispetta limiti di prestazioni rigidi. Si apre in meno di 3 ms, non perde nemmeno un fotogramma quando sfogli le pagine e a riposo usa lo 0% di CPU.

E poi aggiunge quello che l'originale non ha mai avuto.

<img src="../assets/localized/grid.it.jpg" width="860" alt="La griglia di Liftoff dopo l'Organizzazione smart: cartelle per strumenti di sviluppo, ufficio e documenti, contenuti multimediali, utility e altro">

## Funzionalità

### Anteprime delle finestre in tempo reale

Fermati con il puntatore su un'app in esecuzione (oppure premi <kbd>Spazio</kbd> su di essa) e le sue finestre compaiono come miniature. Fai clic su una per passare subito a quella finestra, comprese quelle minimizzate e quelle su altre scrivanie.

<img src="../assets/window-preview.jpg" width="780" alt="Passando il puntatore su un'app in esecuzione compaiono le miniature delle sue finestre">

### Una ricerca che trova app *e* finestre

Scrivi poche lettere. Liftoff cerca tra i nomi delle app, le iniziali (`vsc` → Visual Studio Code), il pinyin per i nomi cinesi e i titoli delle finestre che hai aperto.

<img src="../assets/search.jpg" width="780" alt="Scrivendo nel campo di ricerca, app e finestre vengono filtrate">

### Organizzazione smart

Con un clic tutte le tue app finiscono in cartelle sensate: strumenti di sviluppo, documenti e ufficio, contenuti multimediali, utility… Prima vedi un'anteprima completa, non cambia nulla finché non premi Applica e il layout attuale viene salvato automaticamente in un backup.

Funziona a partire da una tabella integrata con oltre 1.000 app Mac molto diffuse (comprese quelle popolari in Cina, Giappone, Corea e Taiwan), senza andare a intuito: niente AI, niente rete, sempre lo stesso risultato. Manca un'app? Basta una riga in [`AppCategories.json`](../Liftoff/Resources/AppCategories.json), e le pull request sono ben accette.

<img src="../assets/localized/smart-organize.it.png" width="780" alt="Anteprima dell'Organizzazione smart con l'elenco di cartelle e app prima dell'applicazione">

### E molto altro

- **Trascina un'app nel Dock** direttamente dalla griglia: il pannello si toglie di mezzo da solo
- **Importa il layout del vecchio Launchpad**, oppure riparti da zero con l'Organizzazione smart
- Aprilo come preferisci: scorciatoia da tastiera (<kbd>⌃⌘L</kbd> per impostazione predefinita), pizzico con pollice e tre dita, un angolo attivo, l'icona nel Dock oppure `open liftoff://toggle`
- Pagine, cartelle (trascina per unire), trascinamento per riordinare, navigazione da tastiera
- Sfondo sfocato (consumo minimo), sfocatura in tempo reale o un'immagine tua; dimensione di icone ed etichette e colori regolabili
- Supporto multi-schermo · nascondi app · disinstalla app insieme ai file residui · backup e ripristino del layout
- 13 lingue, in base alla lingua del sistema

<img src="../assets/folder.jpg" width="780" alt="Una cartella aperta">

## Prestazioni

Misurate su un Mac reale dall'app stessa (`scripts/selftest.sh` riproduce i numeri sul tuo):

| | |
|---|---|
| Apertura del pannello | **< 3 ms** |
| Ricerca, per ogni tasto | **< 8 ms** |
| Cambio pagina | **0 fotogrammi persi** |
| A riposo | **0% CPU** |

## Privacy

Liftoff **non effettua alcuna connessione di rete**. Le miniature delle finestre vengono catturate e mostrate in locale e non lasciano mai il tuo Mac.
Non fidarti sulla parola: il codice che usa ciascun permesso si trova in [`Liftoff/Preview`](../Liftoff/Preview) (Registrazione schermo e audio di sistema: miniature; Accessibilità: elenco e cambio delle finestre) e in [`Liftoff/Services`](../Liftoff/Services) (scorciatoia da tastiera, angolo attivo, gesto sul trackpad). Anche Little Snitch o LuLu te lo confermeranno.

### Una nota sulle API private

Due funzionalità usano API non documentate di macOS, entrambe caricate dinamicamente e con un fallback: se i simboli scompaiono, la funzione si disattiva da sola invece di andare in crash.

- [`Liftoff/Preview/PrivateAPI.swift`](../Liftoff/Preview/PrivateAPI.swift): SkyLight / HIServices, per elencare le finestre e passare dall'una all'altra (lo stesso approccio di AltTab e Hammerspoon)
- [`Liftoff/Services/TrackpadGesture.swift`](../Liftoff/Services/TrackpadGesture.swift): MultitouchSupport, per il gesto di pizzico (lo stesso approccio di BetterTouchTool e MiddleClick)

## Installazione

Richiede **macOS 26 o versioni successive**.

1. Scarica `Liftoff.zip` da [Releases](https://github.com/firstfu/Liftoff/releases/latest) e decomprimilo.
2. Sposta `Liftoff.app` in `/Applications`.
3. Aprilo. La prima volta macOS lo bloccherà, perché non è ancora notarizzato da Apple: apri **Impostazioni di Sistema → Privacy e sicurezza**, scorri verso il basso e fai clic su **Apri comunque** accanto a *Il Mac ha bloccato Liftoff per garantire la sicurezza.*
4. Concedi i permessi richiesti: **Accessibilità** (elencare e cambiare finestra) e **Registrazione schermo e audio di sistema** (miniature delle finestre, solo in locale).

> Le build sono firmate ad-hoc, quindi dopo ogni aggiornamento macOS ti chiede di riattivare Accessibilità e Registrazione schermo e audio di sistema.

## Lingue

Liftoff segue la lingua del sistema: English, 繁體中文, 简体中文, 日本語, 한국어, Deutsch, Français, Español, Português (Brasil), Italiano, Русский, Türkçe e Nederlands. Per qualsiasi altra lingua si usa l'inglese.

Hai trovato una traduzione poco naturale, o vuoi aggiungere una lingua? Tutti i testi dell'interfaccia stanno in un unico file, [`Liftoff/Resources/Localizable.xcstrings`](../Liftoff/Resources/Localizable.xcstrings): aprilo in Xcode oppure invia una pull request.

## Compilare dal codice sorgente

Richiede Xcode 26 e [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/firstfu/Liftoff.git && cd Liftoff
xcodegen generate
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Liftoff.app
```

Non serve un account Apple: le build sono firmate ad-hoc per impostazione predefinita. Per firmare con il tuo certificato (così macOS mantiene i permessi di Accessibilità e Registrazione schermo e audio di sistema tra una compilazione e l'altra), vedi [`Config/Signing.xcconfig`](../Config/Signing.xcconfig).
Test: sostituisci `build` con `test` nel comando `xcodebuild`. `scripts/install.sh` compila la versione Release, la installa in `/Applications` e registra l'avvio al login.

## Contribuire

Libero e open source, sviluppato da una sola persona: [issue](https://github.com/firstfu/Liftoff/issues/new/choose) e pull request sono molto gradite. I modi più semplici per dare una mano: correggere una traduzione, aggiungere un'app mancante in [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) o segnalare un bug indicando la tua versione di macOS.

## Licenza

[GPLv3](../LICENSE). Sei libero di usarlo, studiarlo, modificarlo e condividerlo; le versioni modificate che distribuisci devono restare open source con la stessa licenza.
