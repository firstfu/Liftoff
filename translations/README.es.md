<div align="center">

<img src="../assets/icon.png" width="128" alt="Icono de Liftoff">

# Liftoff

**El Launchpad que macOS 26 te quitó: de vuelta, más rápido y con previsualización de ventanas en vivo.**

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](../LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
[![Latest release](https://img.shields.io/github/v/release/firstfu/Liftoff)](https://github.com/firstfu/Liftoff/releases/latest)
![Languages](https://img.shields.io/badge/languages-13-brightgreen)

[Descargar](https://github.com/firstfu/Liftoff/releases/latest)

[English](../README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · **Español** · [Português](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md)

<img src="../assets/hero.gif" width="860" alt="Liftoff en acción: abrir, buscar, previsualizar ventanas y abrir una carpeta">

</div>

## Por qué Liftoff

macOS 26 sustituyó la clásica cuadrícula del Launchpad por la lista «Apps». Si te gustaba la cuadrícula (páginas, carpetas, arrastrar para reordenar, escribir para buscar), Liftoff te la devuelve. Está construido desde cero para macOS 26 y con límites de rendimiento estrictos: se abre en menos de 3 ms, no pierde ni un fotograma al cambiar de página y consume un 0 % de CPU en reposo.

Y además añade lo que el original nunca tuvo.

<img src="../assets/localized/grid.es.jpg" width="860" alt="La cuadrícula de Liftoff tras la Organización inteligente: carpetas de herramientas de desarrollo, oficina y documentos, multimedia, utilidades y más">

## Características

### Previsualización de ventanas en vivo

Deja el puntero sobre una app en ejecución (o pulsa <kbd>Espacio</kbd> sobre ella) y sus ventanas aparecerán como miniaturas. Haz clic en una para ir directamente a esa ventana, incluso si está minimizada o en otro escritorio.

<img src="../assets/window-preview.jpg" width="780" alt="Al pasar el puntero sobre una app en ejecución se muestran las miniaturas de sus ventanas">

### Una búsqueda que encuentra apps *y* ventanas

Escribe unas pocas letras. Liftoff busca por nombre de app, por iniciales (`vsc` → Visual Studio Code), por pinyin en los nombres chinos y por los títulos de tus ventanas abiertas.

<img src="../assets/search.jpg" width="780" alt="Al escribir en el campo de búsqueda se filtran apps y ventanas">

### Organización inteligente

Con un clic, toda tu colección de apps se ordena en carpetas con sentido: herramientas de desarrollo, documentos y oficina, multimedia, utilidades… Primero ves una previsualización completa, no cambia nada hasta que pulsas Aplicar y tu disposición actual se guarda automáticamente en una copia de seguridad.

Funciona con una tabla integrada de más de 1.000 apps populares para Mac (incluidas las más usadas en China, Japón, Corea y Taiwán), sin adivinar: sin IA, sin red y con el mismo resultado siempre. ¿Falta alguna app? Basta una línea en [`AppCategories.json`](../Liftoff/Resources/AppCategories.json); los pull requests son bienvenidos.

<img src="../assets/localized/smart-organize.es.png" width="780" alt="Previsualización de la Organización inteligente con las carpetas y apps antes de aplicar los cambios">

### Y más

- **Arrastra una app al Dock** directamente desde la cuadrícula: el panel se aparta solo
- **Importa tu antigua disposición del Launchpad**, o empieza de cero con la Organización inteligente
- Ábrelo como prefieras: atajo de teclado (<kbd>⌃⌘L</kbd> por defecto), gesto de pellizco con el pulgar y tres dedos, una esquina activa, el icono del Dock o `open liftoff://toggle`
- Páginas, carpetas (arrastra para combinar), arrastrar para reordenar y navegación con el teclado
- Fondo de pantalla desenfocado (el de menor consumo), desenfoque en vivo o tu propia imagen; tamaño de iconos, tamaño de etiquetas y colores ajustables
- Compatible con varias pantallas · oculta apps · desinstala apps y sus archivos residuales · copia de seguridad y restauración de tu disposición
- 13 idiomas, según el idioma del sistema

<img src="../assets/folder.jpg" width="780" alt="Una carpeta abierta">

## Rendimiento

Medido por la propia app en un Mac real (`scripts/selftest.sh` reproduce las cifras en el tuyo):

| | |
|---|---|
| Abrir el panel | **< 3 ms** |
| Búsqueda, por pulsación de tecla | **< 8 ms** |
| Cambio de página | **0 fotogramas perdidos** |
| En reposo | **0 % de CPU** |

## Privacidad

Liftoff **no establece ninguna conexión de red**. Las miniaturas de las ventanas se capturan y se muestran en local y nunca salen de tu Mac.
No hace falta que me creas: el código que usa cada permiso está en [`Liftoff/Preview`](../Liftoff/Preview) (Grabación de pantalla: miniaturas; Accesibilidad: listar y cambiar de ventana) y en [`Liftoff/Services`](../Liftoff/Services) (atajo de teclado, esquina activa, gesto del trackpad). Little Snitch o LuLu también te lo confirmarán.

### Nota sobre las API privadas

Dos funciones usan API no documentadas de macOS. Ambas se cargan de forma dinámica y con una alternativa: si los símbolos desaparecen, la función se desactiva sola en lugar de provocar un cierre inesperado.

- [`Liftoff/Preview/PrivateAPI.swift`](../Liftoff/Preview/PrivateAPI.swift): SkyLight / HIServices, para enumerar y cambiar de ventana (el mismo enfoque que AltTab y Hammerspoon)
- [`Liftoff/Services/TrackpadGesture.swift`](../Liftoff/Services/TrackpadGesture.swift): MultitouchSupport, para el gesto de pellizco (el mismo enfoque que BetterTouchTool y MiddleClick)

## Instalación

Requiere **macOS 26 o posterior**.

1. Descarga `Liftoff.zip` desde [Releases](https://github.com/firstfu/Liftoff/releases/latest) y descomprímelo.
2. Mueve `Liftoff.app` a `/Applications`.
3. Ábrelo. macOS lo bloqueará la primera vez porque Apple aún no lo ha notarizado: abre **Ajustes del Sistema → Privacidad y seguridad**, desplázate hacia abajo y haz clic en **Abrir igualmente** junto a *Se ha bloqueado Liftoff para proteger tu Mac.*
4. Concede los permisos que te pida: **Accesibilidad** (listar y cambiar de ventana) y **Grabación de pantalla y del audio del sistema** (miniaturas de ventanas, solo en local).

> Las compilaciones tienen firma ad hoc, así que macOS te pedirá volver a activar Accesibilidad y Grabación de pantalla y del audio del sistema después de cada actualización.

## Idiomas

Liftoff sigue el idioma de tu sistema: English, 繁體中文, 简体中文, 日本語, 한국어, Deutsch, Français, Español, Português (Brasil), Italiano, Русский, Türkçe y Nederlands. Cualquier otro idioma usa inglés.

¿Has visto una traducción poco natural o quieres añadir un idioma? Todo el texto de la interfaz está en un único archivo, [`Liftoff/Resources/Localizable.xcstrings`](../Liftoff/Resources/Localizable.xcstrings): ábrelo en Xcode o envía un pull request.

## Compilar desde el código fuente

Requiere Xcode 26 y [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/firstfu/Liftoff.git && cd Liftoff
xcodegen generate
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Liftoff.app
```

No necesitas cuenta de Apple: las compilaciones usan firma ad hoc por defecto. Para firmar con tu propio certificado (y que macOS conserve los permisos de Accesibilidad y Grabación de pantalla y del audio del sistema entre compilaciones), consulta [`Config/Signing.xcconfig`](../Config/Signing.xcconfig).
Pruebas: sustituye `build` por `test` en el comando `xcodebuild`. `scripts/install.sh` compila en Release, instala en `/Applications` y registra el inicio al arrancar la sesión.

## Contribuir

Libre, de código abierto y hecho por una sola persona: los [issues](https://github.com/firstfu/Liftoff/issues/new/choose) y los pull requests son muy bienvenidos. Las formas más fáciles de ayudar: corregir una traducción, añadir una app que falte a [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) o informar de un error indicando tu versión de macOS.

## Licencia

[GPLv3](../LICENSE). Eres libre de usarlo, estudiarlo, modificarlo y compartirlo; las versiones modificadas que distribuyas deben seguir siendo de código abierto bajo la misma licencia.
