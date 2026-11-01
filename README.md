# OpenGrokBot

Independent Grok Bot client project, with **native macOS as the current priority**, an iOS target, and a Windows desktop app/Setup installer. The desktop layout follows the supplied reference screenshots.

**Live Grok Bot service integration is unfinished.** The apps have working local preview features; they cannot sign in to the real service, sync your Bots, or execute agent tasks. No private protocol, authentication flow, or compatible harness version has been verified. Example messages and handoffs remain offline fixtures. See [harness evidence](docs/HARNESS.md).

## Platforms and builds

| Platform | Implementation | Build |
| --- | --- | --- |
| macOS 14+ | Native SwiftUI/AppKit; Liquid Glass on macOS 26, native material fallback earlier | Universal Apple Silicon/Intel `.app` and `.dmg` |
| iOS 18+ | Native SwiftUI; shared glass controls activate on iOS 26 | Xcode project for simulator and device signing |
| Windows x64 | Electron, isolated renderer, desktop screenshot layout | NSIS Setup `.exe` |

The [downloads page](docs/DOWNLOADS.md) links the desktop installers, native test results, and source review. The Mac development DMG is ad-hoc signed and not notarized. The Windows development installer is unsigned. No signing certificates or account credentials are embedded.

![Native macOS app on the CI display](docs/screenshots/macos-workspace.png)

## macOS first

Open `GrokBot.xcodeproj`, select **GrokBotMac > My Mac**, and run with Xcode 26+. The workspace opens directly, with the reference sidebar, centered Bot header, conversation bubbles, glass composer, app catalog, and settings panel.

To produce the universal Mac installer on a Mac:

```bash
./scripts/build-macos.sh
```

It builds, checks the signature, creates a drag-to-Applications DMG, verifies it, and writes a checksum. [Mac setup and signing details](docs/MACOS.md) explain development installation and Developer ID/notarization options.

For the phone target, select **GrokBot** in the same Xcode project. Follow the [physical iPhone guide](docs/DEVICE_SETUP.md) for team selection, bundle identifiers, Developer Mode, installation, and launch.

For Windows, use the Setup EXE from a successful desktop CI run, or follow the [Windows build guide](docs/WINDOWS.md).

## Working local workflows

- Bot roster and search; create and delete preview Bots.
- Conversations with persistent local notes, per-Bot desktop drafts, honest offline status, and export.
- Connect Apps catalog with search/categories and explicit connection requirements. No false connected counts or successful authorization messages.
- Desktop settings for appearance, local profile preferences, computer status, permissions status, usage status, and updates.
- Device vault on desktop: macOS Keychain or Windows data protection. It is separate from Grok Bot's cloud Vault, and Bots cannot read it.
- Native Apple glass/material controls, system typography, immediate interaction feedback, and reduced-motion/transparency support.

Live agent responses, tasks, streaming, cancellation, tool calls, approvals, artifacts, voice, account login, cloud computer control, connectors, and billing remain unavailable. No model API is substituted for the actual Grok Bot service.

## Architecture

- `GrokBot/Core/`: local models/persistence, origin validation, and a protocol boundary that fails before any connection attempt.
- `GrokBot/App/` and `GrokBot/Features/`: iOS state and screens.
- `GrokBot/Design/GlassChrome.swift`: shared Apple glass with SDK/OS and accessibility fallbacks.
- `GrokBotMac/`: native desktop application, screenshot-based workspace, panels, and device vault.
- `GrokBot/Security/`: Keychain storage. The Mac local vault uses it; no service credential flow is implemented.
- `desktop-windows/`: Electron main/preload boundary, validated local storage, encrypted vault, and renderer.
- `GrokBotTests/`, `GrokBotMacUITests/`, and `scripts/`: native tests, native window captures, browser/native Electron checks, packaging, and static installer inspection.

The native Apple apps have no third-party runtime dependencies. Windows dependencies are pinned in `package-lock.json`. SwiftUI/AppKit provide native platform behavior, while Electron supplies the Windows packaging path. Apple Liquid Glass requires an SDK and OS version that support it; CSS blur on Windows is not presented as the native Apple material.

## Binary inspection and real integration

The uploaded `Grok_Bot_0.78.1.dmg` exceeds the attachment tool's 32 MiB transfer limit. Its bytes have not been inspected. There is no official harness source repository in the workspace. Official product docs establish the Bot/cloud-computer model and Cursor browser sign-in, but do not establish a supported independent client protocol.

On the Mac holding your reference installer:

```bash
./scripts/inspect-dmg.sh "$HOME/Downloads/Grok_Bot_0.78.1.dmg" inspection/0.78.1
```

This mounts read-only, captures selected metadata/checksums/signing diagnostics, and extracts a standard Electron `app.asar` without launching it. [Inspection details](docs/BINARY_INSPECTION.md) explain which small outputs and protocol/auth files are needed next. Extracted vendor code, installers, and local user data are gitignored and not redistributed.

## Data, network, and cost

The apps make no Grok Bot or model requests. Opening an official documentation link uses the system browser. Local notes persist in each platform's application data directory and may enter normal device backups; they are not a secret vault. Mac secure-note values are in Keychain, and Windows values are encrypted with data protection. Revealed desktop secrets clear on loss of app focus.

No backend or self-hosted bridge has been verified or supplied. A phone's `localhost` refers to the phone. A future bridge needs an evidenced upstream protocol, trusted HTTPS, reachable routing, authentication, and preserved approval controls. No TLS bypass or broad ATS exception is included.

The offline features incur no service charges. Real Grok Bot access requires an eligible plan according to the [official mobile requirements](https://docs.x.ai/grok-bot/mobile). Independent-client pricing, rate limits, and service compatibility are unknown.

## Verification

Mac native compilation, tests, and DMG creation run in GitHub Actions. Windows Setup builds and native Electron smoke tests use a Windows runner; iOS tests use an iPhone simulator. Current results and remaining limits are recorded in [verification results](docs/VERIFICATION.md).

Local checks:

```bash
python3 -m pip install -r scripts/check-requirements.txt
python3 scripts/check_project.py
python3 -m unittest discover -s scripts -p 'test_*.py' -v
npm ci
npm run test:desktop
CHROMIUM_PATH=/path/to/installed/chromium npm run test:ui
```

Swift syntax parsing is separate from Xcode compilation. Simulator tests do not verify a physical phone. Installer creation does not establish live Grok Bot interoperability or notarization.

## License

Original code and geometric artwork in this repository are [MIT licensed](LICENSE). This independent project is not affiliated with xAI or Cursor. Vendor binaries, renderer code, and artwork are not bundled. The supplied Apple Design guidance informs the materials, motion, typography, and accessibility choices.
