<div align="center">

<img src="../assets/icon.png" width="128" alt="Ícone do Liftoff">

# Liftoff

**O Launchpad que o macOS 26 tirou de você: de volta, mais rápido e com pré-visualização ao vivo das janelas.**

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](../LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
[![Latest release](https://img.shields.io/github/v/release/firstfu/Liftoff)](https://github.com/firstfu/Liftoff/releases/latest)
![Languages](https://img.shields.io/badge/languages-13-brightgreen)

[Baixar](https://github.com/firstfu/Liftoff/releases/latest)

[English](../README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · **Português (Brasil)** · [Italiano](README.it.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [Nederlands](README.nl.md)

<a href="https://github.com/firstfu/Liftoff/releases/latest"><b>Baixar o Liftoff.zip</b></a>
&nbsp;·&nbsp;
<code>brew install --cask firstfu/tap/liftoff</code>

<img src="../assets/hero.gif" width="860" alt="Liftoff em ação: abrir, buscar, pré-visualizar janelas e abrir uma pasta">

</div>

> [!NOTE]
> O Liftoff exige o **macOS 26 ou posterior**. Ele **ainda não é notarizado pela Apple**, então o macOS bloqueia a primeira abertura: abra Ajustes do Sistema → Privacidade e Segurança e clique em **Abrir Mesmo Assim** uma vez ([passo a passo](#instalação)). Todo o código está aqui, e [para que serve cada permissão](#permissões-em-resumo) está explicado mais abaixo.

## Por que o Liftoff

O macOS 26 trocou a clássica grade do Launchpad pela lista "Apps". Se você gostava da grade, com páginas, pastas, arrastar para reorganizar e digitar para buscar, o Liftoff traz tudo de volta. Foi feito do zero para o macOS 26 e segue limites rígidos de desempenho: abre em menos de 3 ms, nunca perde um quadro ao trocar de página e usa 0% de CPU em repouso.

E ainda acrescenta o que o original nunca teve.

<img src="../assets/localized/grid.pt-BR.jpg" width="860" alt="A grade do Liftoff após a Organização inteligente: pastas de Ferramentas para Desenvolvedores, Escritório e Documentos, Mídia, Utilitários e mais">

## Recursos

### Pré-visualização ao vivo das janelas

Deixe o cursor parado sobre um app aberto (ou pressione <kbd>Espaço</kbd> nele) e as janelas dele aparecem como miniaturas. Clique em uma para ir direto àquela janela, inclusive as minimizadas e as de outras mesas.

<img src="../assets/window-preview.jpg" width="780" alt="Ao passar o cursor sobre um app aberto, aparecem miniaturas das janelas dele">

### Busca que encontra apps *e* janelas

Digite algumas letras. O Liftoff encontra pelo nome do app, pelas iniciais (`vsc` → Visual Studio Code), pelo pinyin de nomes em chinês e pelos títulos das suas janelas abertas.

<img src="../assets/search.jpg" width="780" alt="Ao digitar no campo de busca, apps e janelas são filtrados">

### Organização inteligente

Um clique organiza toda a sua coleção de apps em pastas que fazem sentido: Ferramentas para Desenvolvedores, Documentos e Escritório, Mídia, Utilitários… Você vê uma pré-visualização completa antes, nada muda até você clicar em Aplicar, e o layout atual é salvo em backup automaticamente.

Ela usa uma tabela interna com mais de 1.000 apps populares de Mac (incluindo apps famosos na China, no Japão, na Coreia e em Taiwan), sem adivinhação: sem IA, sem rede, sempre com o mesmo resultado. Faltou um app? É só uma linha em [`AppCategories.json`](../Liftoff/Resources/AppCategories.json). Pull requests são bem-vindos.

<img src="../assets/localized/smart-organize.pt-BR.png" width="780" alt="Pré-visualização da Organização inteligente com as pastas e os apps antes de aplicar">

### E mais

- **Arraste um app para o Dock** direto da grade; o painel sai da frente sozinho
- **Importe o layout do seu antigo Launchpad** ou comece do zero com a Organização inteligente
- Abra do jeito que preferir: atalho de teclado (<kbd>⌃⌘L</kbd> por padrão), pinça com o polegar e três dedos, um dos Cantos de Acesso Rápido, o ícone no Dock ou `open liftoff://toggle`
- Páginas, pastas (arraste para mesclar), arrastar para reordenar e navegação pelo teclado
- Imagem de fundo desfocada (menor consumo de energia), desfoque ao vivo ou uma imagem sua; tamanho dos ícones, tamanho dos rótulos e cores ajustáveis
- Compatível com várias telas · ocultar apps · desinstalar apps junto com os arquivos restantes · backup e restauração do layout
- 13 idiomas, seguindo o idioma do sistema

<img src="../assets/folder.jpg" width="780" alt="Uma pasta aberta">

## Desempenho

Medido pelo próprio app em um Mac de verdade (`scripts/selftest.sh` reproduz os números no seu):

| | |
|---|---|
| Abrir o painel | **< 3 ms** |
| Busca, por tecla digitada | **< 8 ms** |
| Troca de página | **0 quadros perdidos** |
| Em repouso | **0% de CPU** |

## Privacidade

O Liftoff **não faz nenhuma conexão de rede**, a menos que você peça para buscar atualizações. As miniaturas das janelas são capturadas e exibidas localmente e nunca saem do seu Mac.
A única conexão possível é a busca de atualizações: uma requisição à API do GitHub para ler o número da versão mais recente, enviada somente quando você clica em **Buscar Atualizações…** ou ativa **Verificar atualizações toda semana** nos Ajustes (desativado por padrão). Nenhum dado sobre você é enviado.

Não precisa acreditar na minha palavra: o código que usa cada permissão está em [`Liftoff/Preview`](../Liftoff/Preview) (Gravação do Áudio do Sistema e da Tela: miniaturas; Acessibilidade: listar e alternar janelas) e em [`Liftoff/Services`](../Liftoff/Services) (atalho de teclado, canto ativo, gesto no trackpad e a busca de atualizações em `UpdateChecker.swift`). O Little Snitch ou o LuLu também confirmam.

### Uma observação sobre APIs privadas

Dois recursos usam APIs não documentadas do macOS, ambas carregadas dinamicamente e com alternativa: se os símbolos desaparecerem, o recurso se desativa sozinho em vez de travar o app:

- [`Liftoff/Preview/PrivateAPI.swift`](../Liftoff/Preview/PrivateAPI.swift): SkyLight / HIServices, para listar e alternar janelas (a mesma abordagem do AltTab e do Hammerspoon)
- [`Liftoff/Services/TrackpadGesture.swift`](../Liftoff/Services/TrackpadGesture.swift): MultitouchSupport, para o gesto de pinça (a mesma abordagem do BetterTouchTool e do MiddleClick)

## Instalação

**Homebrew**: `brew install --cask firstfu/tap/liftoff` (`brew upgrade --cask liftoff`)

1. Baixe o `Liftoff.zip` em [Releases](https://github.com/firstfu/Liftoff/releases/latest) e descompacte.
2. Mova o `Liftoff.app` para `/Applications`.
3. Abra o app. Na primeira vez, o macOS vai bloqueá-lo, porque ele ainda não é notarizado pela Apple: abra **Ajustes do Sistema → Privacidade e Segurança**, role até o fim e clique em **Abrir Mesmo Assim** ao lado de *O app Liftoff foi bloqueado para proteger o Mac.*
4. Conceda as permissões solicitadas: **Acessibilidade** (listar e alternar janelas) e **Gravação do Áudio do Sistema e da Tela** (miniaturas das janelas, apenas localmente).

Requer **macOS 26 ou posterior**, Apple silicon ou Intel.

### Atualizando

Substitua o `Liftoff.app` em `/Applications` pela nova versão. Os builds têm assinatura ad-hoc, então o macOS trata cada versão como um app novo: você clica em **Abrir Mesmo Assim** uma vez, e a Gravação do Áudio do Sistema e da Tela e a Acessibilidade precisam ser ativadas de novo (se um botão parecer ativado mas não funcionar, remova o Liftoff da lista com **−** e adicione-o novamente).
Para ficar sabendo de novas versões: escolha **Buscar Atualizações…** no menu da barra de menus ou nos Ajustes, ative **Verificar atualizações toda semana** nos Ajustes (desativado por padrão) ou use **Watch → Custom → Releases** nesta página.

## Permissões em resumo

| Permissão | Necessária? | Para quê | Se você pular |
|---|---|---|---|
| **Gravação do Áudio do Sistema e da Tela** | Só para a pré-visualização de janelas | Miniaturas e títulos das janelas (capturados e exibidos apenas no seu Mac) | Sem pré-visualização de janelas; o Liftoff continua sendo um launcher |
| **Acessibilidade** | Opcional | Listar janelas minimizadas e ir exatamente para a janela em que você clicou | Janelas minimizadas não aparecem; a troca fica menos precisa |

Nenhuma outra permissão é solicitada. O launcher em si não precisa de nenhuma permissão.

## Perguntas frequentes

<details>
<summary><b>O macOS diz que o "Liftoff foi bloqueado para proteger o Mac"</b></summary>

O Liftoff ainda não é notarizado pela Apple. Abra Ajustes do Sistema → Privacidade e Segurança, role até o fim e clique em **Abrir Mesmo Assim** ao lado da mensagem. É um passo único por versão.
</details>

<details>
<summary><b>A pré-visualização das janelas não aparece ou aparece sem miniaturas</b></summary>

Confira se **Gravação do Áudio do Sistema e da Tela** (necessária para as pré-visualizações) e, opcionalmente, **Acessibilidade** (janelas minimizadas, troca precisa) estão ativadas para o Liftoff em Ajustes do Sistema → Privacidade e Segurança. Se um botão parecer ativado mas nada funcionar (comum após uma atualização), remova o Liftoff da lista com **−** e adicione-o novamente.
</details>

<details>
<summary><b>Perco as permissões ao atualizar?</b></summary>

Sim, com as versões assinadas ad-hoc: o macOS vê cada versão como um app novo, então a Gravação do Áudio do Sistema e da Tela e a Acessibilidade precisam ser permitidas de novo. Compilar você mesmo com o seu próprio certificado evita isso. Veja [`Config/Signing.xcconfig`](../Config/Signing.xcconfig).
</details>

<details>
<summary><b>O atalho de teclado, o gesto de pinça ou o canto ativo não abre o Liftoff</b></summary>

Outro app pode já estar usando o atalho (Ajustes → Acionadores mostra um aviso); escolha outro. O gesto de pinça desativa temporariamente o gesto de pinça do próprio macOS para "Apps" enquanto o Liftoff está em execução e o restaura quando você o desativa ou encerra o app. `open liftoff://toggle` sempre funciona.
</details>

<details>
<summary><b>Como desinstalo?</b></summary>

Encerre o Liftoff pela barra de menus, apague o `Liftoff.app` de `/Applications` e remova-o de Ajustes do Sistema → Geral → Itens de Início de Sessão e Extensões se você ativou *Abrir no Início da Sessão*. Para remover também os ajustes dele: `defaults delete com.firstfu.Liftoff` e apague `~/Library/Caches/com.firstfu.Liftoff`.
</details>

## Como ele se diferencia de ferramentas parecidas

O [LaunchNext](https://github.com/RoversX/LaunchNext) é um bom projeto de código aberto, ativo: é notarizado, importa o layout antigo do Launchpad e tem busca aproximada e pastas. Se é isso que você precisa, use-o. O que o Liftoff acrescenta: miniaturas ao vivo das janelas de um app em execução (clique para ir até elas, inclusive as minimizadas), busca que também encontra títulos de janelas, Organização inteligente com um clique (tabela de consulta embutida, sem IA, com pré-visualização antes), arrastar apps da grade para o Dock e números de desempenho que você pode reproduzir. A contrapartida hoje: o LaunchNext é notarizado e o Liftoff ainda não.

## Idiomas

O Liftoff segue o idioma do sistema: English, 繁體中文, 简体中文, 日本語, 한국어, Deutsch, Français, Español, Português (Brasil), Italiano, Русский, Türkçe e Nederlands. Qualquer outro idioma usa o inglês.

Encontrou uma tradução estranha ou quer adicionar um idioma? Todo o texto da interface fica em um único arquivo, [`Liftoff/Resources/Localizable.xcstrings`](../Liftoff/Resources/Localizable.xcstrings). Abra no Xcode ou envie um pull request.

## Compilar a partir do código-fonte

Requer Xcode 26 e [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/firstfu/Liftoff.git && cd Liftoff
xcodegen generate
xcodebuild -project Liftoff.xcodeproj -scheme Liftoff -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Liftoff.app
```

Não precisa de conta Apple: os builds têm assinatura ad-hoc por padrão. Para assinar com o seu próprio certificado (assim o macOS mantém as permissões de Acessibilidade e Gravação do Áudio do Sistema e da Tela entre recompilações), veja [`Config/Signing.xcconfig`](../Config/Signing.xcconfig).
Testes: troque `build` por `test` no comando `xcodebuild`. O `scripts/install.sh` compila em Release, instala em `/Applications` e registra a abertura no início da sessão.

## Contribuindo

Gratuito e de código aberto, feito por uma pessoa só. [Issues](https://github.com/firstfu/Liftoff/issues/new/choose) e pull requests são muito bem-vindos. As formas mais fáceis de ajudar: corrigir uma tradução, adicionar um app que falta em [`AppCategories.json`](../Liftoff/Resources/AppCategories.json) ou relatar um bug informando a sua versão do macOS.

## Licença

[GPLv3](../LICENSE). Você pode usar, estudar, modificar e compartilhar à vontade; versões modificadas que você distribuir devem continuar de código aberto sob a mesma licença.
