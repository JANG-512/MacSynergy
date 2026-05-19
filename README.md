# MacSynergy

> AI-powered text selection overlay for macOS — select text anywhere, get instant AI actions.

![macOS](https://img.shields.io/badge/macOS-15%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## What is MacSynergy?

MacSynergy watches for text selections across **any macOS app**. The moment you drag-select text, a subtle **`+` button** floats near your cursor. Click it to instantly:

| Action | Description |
|--------|-------------|
| 요약하기 | Summarize the selected text |
| 번역하기 | Translate (Korean ↔ English auto-detect) |
| 다시쓰기 | Rewrite more clearly |
| 글쓰기 | Write new content with a custom prompt |
| 분석하기 | Deep analysis of the text |

Results open in the MacSynergy overlay — a sleek floating window that stays out of your way.

## Features

- 🖱 **Zero-friction** — drag to select, click `+`, done
- 🌐 **System-wide** — works in any app (browsers, editors, Slack, etc.)
- ⚡ **Instant** — actions appear in a floating panel, no app switching
- ⌨ **Global hotkey** — `Shift + Space` opens MacSynergy anytime
- 🔒 **Privacy-first** — your API key stays on-device

## Requirements

- macOS 15 (Sequoia) or later
- An [Anthropic API key](https://console.anthropic.com/)
- **Accessibility permission** (for text capture) — granted once, persists across updates

## Installation

### Download DMG (Recommended)

1. Download `MacSynergy.dmg` from [Releases](../../releases)
2. Open the DMG, drag **MacSynergy.app** to Applications
3. Launch MacSynergy from Applications
4. Grant **Accessibility** permission when prompted
5. Enter your Anthropic API key in the app

### Build from Source

```bash
git clone https://github.com/Antigravity-Inc/MacSynergy.git
cd MacSynergy
./install.sh
```

> Requires Xcode command-line tools: `xcode-select --install`

## Usage

1. **Select any text** in any app by dragging your mouse
2. Click the **`+` button** that appears near your selection
3. Choose an action from the floating menu
4. Results appear in the MacSynergy panel

Or press **`Shift + Space`** to open MacSynergy directly and type a prompt.

## Building a DMG

```bash
./package.sh
```

This produces `MacSynergy-1.0.0.dmg` ready for distribution.

## Architecture

```
MacSynergy/
├── Sources/
│   ├── App/
│   │   └── HotkeyManager.swift          # Carbon global hotkey (no Accessibility needed)
│   ├── Selection/
│   │   ├── SelectionMonitor.swift        # Mouse drag detection
│   │   └── SelectionOverlayController.swift  # + button + action menu panels
│   ├── UI/
│   │   ├── MainLauncherView.swift        # Main app UI
│   │   ├── QuickActionMenuView.swift     # Floating action menu
│   │   └── ...
│   ├── ViewModel/
│   │   └── MacSynergyViewModel.swift     # AI request orchestration
│   └── Window/
│       ├── AppDelegate.swift
│       └── WindowController.swift
├── MacSynergy.app/                       # Pre-built app bundle
├── install.sh                            # Build + run script
└── package.sh                            # DMG packaging script
```

## Co-creators

| Name | Role |
|------|------|
| **Jang Jinuk** | Product Vision & Design |
| **Antigravity** | Engineering Lead |
| **Claude** (Anthropic) | AI Pair Programmer |

## License

MIT License — see [LICENSE](LICENSE) for details.

---

*Built with ❤️ using Swift + SwiftUI + AppKit*
