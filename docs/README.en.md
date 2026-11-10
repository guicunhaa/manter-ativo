# Manter Ativo

**See which local AI agents are using your Mac.** A native SwiftUI menu bar app shows memory, CPU and root process counts for assistants, coding CLIs and MCP servers. Its keep-awake agent continues running after the panel closes.

[Website](https://guicunhaa.github.io/manter-ativo/) · [Download Beta 1 for macOS](https://github.com/guicunhaa/manter-ativo/releases/download/v2.1-beta.1/Manter-Ativo-2.1-beta.1-macOS-universal.zip) · [Português](../README.md) · [20-second walkthrough](manter-ativo.mp4?raw=true)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="painel-escuro.png">
  <img src="painel.png" alt="The native Mac dashboard, with a summary of memory use, a ranked agent list and four system metrics.">
</picture>

*The app interface is in Brazilian Portuguese. The screenshots and walkthrough use sample data.*

## Install Beta 1

The ZIP contains a universal macOS app for Apple silicon and Intel, targeting macOS 15 or later. Unzip it, drag **Manter Ativo.app** to Applications and open it in Finder. The dashboard opens on first launch. Xcode is only needed to build from source. [Release notes and SHA-256](https://github.com/guicunhaa/manter-ativo/releases/tag/v2.1-beta.1)

**This technical beta uses an ad hoc signature.** The Gatekeeper distribution assessment rejected the bundle. macOS may block the downloaded app on first launch. Developer ID signing and Apple notarization are planned for a future distribution.

## Build from source

Use Xcode 26 or later with its command-line tools selected. Check out the tagged source to reproduce this beta.

```sh
git clone --branch v2.1-beta.1 --depth 1 https://github.com/guicunhaa/manter-ativo.git
cd manter-ativo
./script/build_and_run.sh --install
```

Choose **Abrir painel** in the menu bar to open the dashboard. **Agora** shows the three largest agents by memory. Choose **Ver agentes** to search or sort the full list by CPU, memory or copies. Each root counts as one copy. Its children contribute their CPU and memory. CPU can exceed 100% when an agent uses multiple cores.

## Keep-awake modes

| Control | Effect |
| --- | --- |
| **Tela** | Keeps the display awake. Closing the lid can still put the Mac to sleep. |
| **Máquina** | Disables system sleep, even after quitting the app. Installing the power helper requires administrator approval. |
| **Desligada** | Restores sleep on battery. On external power, the system and display sleep timers stay at zero. |

**Mesa** and **Bolso** suggest desk and mobile settings. Changes require confirmation. Activity stays on the Mac. Detection covers local processes. Browser tabs and cloud-only agents are outside its scope.

## Build and test

Run `swift test` from the project directory. To build and verify a local app bundle without installing or launching it, run `./script/build_and_run.sh --bundle`. The result is in `dist/Manter Ativo.app`.

Maintained by Gui Cunha. [MIT license](../LICENSE) · [Issue tracker](https://github.com/guicunhaa/manter-ativo/issues)
