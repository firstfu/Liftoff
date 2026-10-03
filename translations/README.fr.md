<div align="center">

<img src="../assets/icon.png" width="128" alt="Icône de Liftoff">

# Liftoff

**Le Launchpad que macOS 26 vous a retiré — de retour, plus rapide, avec des aperçus de fenêtres en direct.**

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](../LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
[![Latest release](https://img.shields.io/github/v/release/firstfu/Liftoff)](https://github.com/firstfu/Liftoff/releases/latest)
![Languages](https://img.shields.io/badge/languages-13-brightgreen)

<a href="https://github.com/firstfu/Liftoff/releases/latest"><b>Télécharger Liftoff.zip</b></a>

[English](../README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Deutsch](README.de.md) · **Français** · [Español](README.es.md) · [Português](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md)

<img src="../assets/hero.gif" width="860" alt="Liftoff en action : ouverture, recherche, aperçu des fenêtres, ouverture d’un dossier">

</div>

> [!NOTE]
> Liftoff nécessite **macOS 26 ou version ultérieure**. Il n’est **pas encore notarisé par Apple**, donc macOS bloque le premier lancement : ouvrez Réglages Système → Confidentialité et sécurité et cliquez une fois sur **Ouvrir quand même** ([marche à suivre](#installation)). Tout le code est ici, et [à quoi sert chaque autorisation](#aperçu-des-autorisations) est détaillé plus bas.

## Pourquoi Liftoff

macOS 26 a remplacé la grille du Launchpad par une simple liste « Apps ». Si vous aimiez la grille — pages, dossiers, glisser pour réorganiser, taper pour chercher — Liftoff vous la rend. Il a été conçu de zéro pour macOS 26, avec des exigences de performance strictes : il s’ouvre en moins de 3 ms, ne perd pas une image pendant le changement de page et consomme 0 % de CPU au repos.

Et il ajoute ce que l’original n’a jamais eu.

<img src="../assets/localized/grid.fr.jpg" width="860" alt="La grille de Liftoff après l’Organisation intelligente : des dossiers Outils de développement, Bureautique et documents, Médias, Utilitaires, etc.">

## Fonctionnalités

### Aperçu des fenêtres en direct

Laissez le pointeur sur une app ouverte (ou appuyez sur <kbd>Espace</kbd>) et ses fenêtres apparaissent sous forme de miniatures. Cliquez sur l’une d’elles pour passer directement à cette fenêtre, y compris si elle est réduite ou située sur un autre bureau.

<img src="../assets/window-preview.jpg" width="780" alt="Survoler une app ouverte affiche les miniatures de ses fenêtres">

### Une recherche qui trouve les apps *et* les fenêtres

Tapez quelques lettres. Liftoff reconnaît les noms d’apps, les initiales (`vsc` → Visual Studio Code), le pinyin pour les noms chinois, ainsi que les titres de vos fenêtres ouvertes.

<img src="../assets/search.jpg" width="780" alt="La saisie dans le champ de recherche filtre les apps et les fenêtres">

### Organisation intelligente

Un clic range toute votre collection d’apps dans des dossiers cohérents : Outils de développement, Bureautique et documents, Médias, Utilitaires… Vous voyez d’abord un aperçu complet, rien ne change tant que vous n’appuyez pas sur Appliquer, et votre disposition actuelle est sauvegardée automatiquement.

Le classement repose sur une table intégrée de plus de 1 000 apps Mac populaires (dont des apps courantes en Chine, au Japon, en Corée et à Taïwan), pas sur des suppositions : pas d’IA, pas de réseau, et le même résultat à chaque fois. Il manque une app ? Il suffit d’une ligne dans [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) — les pull requests sont les bienvenues.

<img src="../assets/localized/smart-organize.fr.png" width="780" alt="Aperçu de l’Organisation intelligente avec la liste des dossiers et des apps avant application">

### Et ce n’est pas tout

- **Glissez une app vers le Dock** directement depuis la grille — le panneau s’efface tout seul
- **Importez l’ancienne disposition de votre Launchpad**, ou repartez de zéro avec l’Organisation intelligente
- Ouvrez-le comme vous voulez : raccourci clavier (<kbd>⌃⌘L</kbd> par défaut), pincement pouce + trois doigts, un coin actif, l’icône du Dock ou `open liftoff://toggle`
- Pages, dossiers (glissez pour fusionner), réorganisation par glisser-déposer, navigation au clavier
- Fond d’écran flou (le plus économe en énergie), flou en direct ou votre propre image ; taille des icônes, taille des légendes et couleurs réglables
- Gestion de plusieurs moniteurs · masquage d’apps · désinstallation d’apps avec leurs fichiers résiduels · sauvegarde et restauration de votre disposition
- 13 langues, selon la langue du système

<img src="../assets/folder.jpg" width="780" alt="Un dossier ouvert">

## Performances

Mesuré sur un vrai Mac par l’app elle-même (`scripts/selftest.sh` reproduit ces chiffres sur le vôtre) :

| | |
|---|---|
| Ouverture du panneau | **< 3 ms** |
| Recherche, par frappe | **< 8 ms** |
| Changement de page | **0 image perdue** |
| Au repos | **0 % de CPU** |

## Confidentialité

Liftoff **n’établit aucune connexion réseau**, sauf si vous lui demandez de rechercher des mises à jour. Les miniatures des fenêtres sont capturées et affichées en local, et ne quittent jamais votre Mac.
La seule connexion possible est la recherche de mises à jour : une requête à l’API GitHub pour lire le dernier numéro de version, envoyée uniquement lorsque vous cliquez sur **Rechercher les mises à jour…** ou activez **Rechercher les mises à jour chaque semaine** dans les réglages (désactivé par défaut). Aucune donnée vous concernant n’est envoyée.

Ne me croyez pas sur parole : le code qui utilise chaque autorisation se trouve dans [`Liftoff/Preview`](../Liftoff/Preview) (Enregistrement de l’écran : miniatures ; Accessibilité : liste des fenêtres et changement de fenêtre) et [`Liftoff/Services`](../Liftoff/Services) (raccourci clavier, coin actif, geste au trackpad, et la recherche de mises à jour dans `UpdateChecker.swift`). Little Snitch ou LuLu le confirmeront aussi.

### À propos des API privées

Deux fonctionnalités utilisent des API macOS non documentées, toutes deux chargées dynamiquement avec une solution de repli : si les symboles disparaissent, la fonctionnalité se désactive d’elle-même au lieu de planter.

- [`Liftoff/Preview/PrivateAPI.swift`](../Liftoff/Preview/PrivateAPI.swift) — SkyLight / HIServices, pour lister les fenêtres et passer de l’une à l’autre (même approche qu’AltTab et Hammerspoon)
- [`Liftoff/Services/TrackpadGesture.swift`](../Liftoff/Services/TrackpadGesture.swift) — MultitouchSupport, pour le geste de pincement (même approche que BetterTouchTool et MiddleClick)

## Installation

1. Téléchargez `Liftoff.zip` depuis les [Releases](https://github.com/firstfu/Liftoff/releases/latest) et décompressez-le.
2. Déplacez `Liftoff.app` dans `/Applications`.
3. Ouvrez-le. macOS le bloquera la première fois, car il n’est pas encore notarisé par Apple : ouvrez **Réglages Système → Confidentialité et sécurité**, faites défiler vers le bas et cliquez sur **Ouvrir quand même** à côté de *« Liftoff » a été bloqué pour protéger votre Mac.*
4. Accordez les autorisations demandées : **Accessibilité** (lister les fenêtres et passer de l’une à l’autre) et **Enregistrement de l’écran et des sons du système** (miniatures des fenêtres, en local uniquement).

Nécessite **macOS 26 ou version ultérieure**, Apple silicon ou Intel.

### Mise à jour

Remplacez `Liftoff.app` dans `/Applications` par la nouvelle version. Les versions sont signées ad hoc : macOS considère donc chaque version comme une nouvelle app. Vous cliquez une fois sur **Ouvrir quand même**, et Enregistrement de l’écran et des sons du système ainsi qu’Accessibilité doivent être réactivés (si un réglage semble activé mais ne fait rien, retirez Liftoff de la liste avec **−** puis ajoutez-le de nouveau).
Pour être informé des nouvelles versions : choisissez **Rechercher les mises à jour…** dans le menu de la barre des menus ou dans les réglages, activez **Rechercher les mises à jour chaque semaine** dans les réglages (désactivé par défaut), ou utilisez **Watch → Custom → Releases** sur cette page.

## Aperçu des autorisations

| Autorisation | Nécessaire ? | Pourquoi | Si vous l’ignorez |
|---|---|---|---|
| **Enregistrement de l’écran et des sons du système** | Uniquement pour les aperçus de fenêtres | Miniatures et titres des fenêtres (capturés et affichés uniquement sur votre Mac) | Pas d’aperçus de fenêtres ; Liftoff reste un lanceur à part entière |
| **Accessibilité** | Facultative | Lister les fenêtres réduites et passer exactement à la fenêtre sur laquelle vous avez cliqué | Les fenêtres réduites ne sont pas listées ; le changement de fenêtre est moins précis |

Rien d’autre n’est demandé. Le lanceur lui-même ne nécessite aucune autorisation.

## FAQ

<details>
<summary><b>macOS indique « Liftoff » a été bloqué pour protéger votre Mac</b></summary>

Liftoff n’est pas encore notarisé par Apple. Ouvrez Réglages Système → Confidentialité et sécurité, faites défiler vers le bas et cliquez sur **Ouvrir quand même** à côté du message. C’est une étape à faire une seule fois par version.
</details>

<details>
<summary><b>Les aperçus de fenêtres n’apparaissent pas ou n’affichent aucune miniature</b></summary>

Vérifiez que **Enregistrement de l’écran et des sons du système** (nécessaire pour les aperçus) et, facultativement, **Accessibilité** (fenêtres réduites, changement de fenêtre précis) sont activés pour Liftoff dans Réglages Système → Confidentialité et sécurité. Si un réglage semble activé mais que rien ne fonctionne (fréquent après une mise à jour), retirez Liftoff de la liste avec **−** puis ajoutez-le de nouveau.
</details>

<details>
<summary><b>Perd-on les autorisations lors d’une mise à jour ?</b></summary>

Oui, avec les versions signées ad hoc : macOS considère chaque version comme une nouvelle app, donc Enregistrement de l’écran et des sons du système et Accessibilité doivent être autorisés de nouveau. Compiler l’app vous-même avec votre propre certificat évite cela — voir [`Config/Signing.xcconfig`](../Config/Signing.xcconfig).
</details>

<details>
<summary><b>Le raccourci clavier, le geste de pincement ou le coin actif ne l’ouvre pas</b></summary>

Une autre app utilise peut-être déjà ce raccourci (Réglages → Déclenchement affiche un avertissement) ; choisissez-en un autre. Le geste de pincement désactive temporairement le geste de pincement de macOS pour « Apps » tant que Liftoff est en cours d’exécution, et le rétablit quand vous le désactivez ou quittez l’app. `open liftoff://toggle` fonctionne toujours.
</details>

<details>
<summary><b>Comment le désinstaller ?</b></summary>

Quittez Liftoff depuis la barre des menus, supprimez `Liftoff.app` de `/Applications`, puis retirez-le de Réglages Système → Général → Ouverture et extensions si vous aviez activé *Ouvrir avec la session*. Pour supprimer aussi ses réglages : `defaults delete com.firstfu.Liftoff` et supprimez `~/Library/Caches/com.firstfu.Liftoff`.
</details>

## En quoi il diffère d’outils similaires

[LaunchNext](https://github.com/RoversX/LaunchNext) est un bon projet open source, actif : il est notarisé, importe l’ancienne disposition de Launchpad, et propose recherche approximative et dossiers. Si c’est ce qu’il vous faut, utilisez-le. Ce que Liftoff ajoute : des miniatures en direct des fenêtres d’une app en cours d’exécution (un clic pour y aller, fenêtres réduites comprises), une recherche qui trouve aussi les titres de fenêtres, l’Organisation intelligente en un clic (table de correspondance intégrée, sans IA, avec aperçu préalable), le glisser d’apps de la grille vers le Dock, et des chiffres de performance que vous pouvez reproduire. Le compromis aujourd’hui : LaunchNext est notarisé, pas encore Liftoff.

## Langues

Liftoff suit la langue de votre système : English, 繁體中文, 简体中文, 日本語, 한국어, Deutsch, Français, Español, Português (Brasil), Italiano, Русский, Türkçe et Nederlands. Toute autre langue retombe sur l’anglais.

Une traduction maladroite, ou l’envie d’ajouter une langue ? Tous les textes de l’interface se trouvent dans un seul fichier, [`Liftoff/Resources/Localizable.xcstrings`](../Liftoff/Resources/Localizable.xcstrings) — ouvrez-le dans Xcode, ou envoyez une pull request.

## Compiler depuis les sources

Nécessite Xcode 26 et [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/firstfu/Liftoff.git && cd Liftoff
xcodegen generate
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Liftoff.app
```

Aucun compte Apple nécessaire : les builds sont signés ad hoc par défaut. Pour signer avec votre propre certificat (afin que macOS conserve les autorisations Accessibilité et Enregistrement de l’écran et des sons du système d’une compilation à l’autre), voir [`Config/Signing.xcconfig`](../Config/Signing.xcconfig).
Tests : remplacez `build` par `test` dans la commande `xcodebuild`. `scripts/install.sh` compile en Release, installe dans `/Applications` et enregistre l’ouverture à la session.

## Contribuer

Libre et open source, développé par une seule personne — les [issues](https://github.com/firstfu/Liftoff/issues/new/choose) et les pull requests sont les bienvenues. Les moyens les plus simples d’aider : corriger une traduction, ajouter une app manquante à [`AppCategories.json`](../Liftoff/Resources/AppCategories.json), ou signaler un bug en précisant votre version de macOS.

## Licence

[GPLv3](../LICENSE). Vous êtes libre de l’utiliser, de l’étudier, de le modifier et de le partager ; les versions modifiées que vous distribuez doivent rester open source sous la même licence.
