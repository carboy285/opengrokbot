# Development downloads · 0.4.0

Built from source commit `b478151f50a3db637604ee088bffe993066a8ce2`. [Desktop tests and packaging](https://github.com/carboy285/opengrokbot/actions/runs/41266068805) passed.

| Download | Contents |
| --- | --- |
| [macOS universal installer](https://github.com/carboy285/opengrokbot/actions/runs/41266068805/artifacts/13067129143) | ZIP containing `OpenGrokBot-0.4.0-mac-universal.dmg` and SHA-256; Apple Silicon/Intel, macOS 14+ |
| [Windows x64 installer](https://github.com/carboy285/opengrokbot/actions/runs/41266068805/artifacts/13066909956) | ZIP containing `OpenGrokBot-0.4.0-Windows-x64-Setup.exe` |
| [Native Mac screenshots](https://github.com/carboy285/opengrokbot/actions/runs/41266068805/artifacts/13066329539) | Actual side panel, chat, setup, Composio, and settings captures |
| [Native Mac test results](https://github.com/carboy285/opengrokbot/actions/runs/41266068805/artifacts/13066678918) | XCTest bundles: 29 unit tests and 2 UI tests passed |
| [Xcode and Windows source](https://github.com/carboy285/opengrokbot/archive/refs/heads/codex/macos-client.zip) | Full source ZIP. Open `GrokBot.xcodeproj`; choose **GrokBot** for iOS or **GrokBotMac** for Mac |
| [Source review](https://github.com/carboy285/opengrokbot/pull/1) | Draft PR with Apple/Windows sources, packaging, tests, and setup documentation |

GitHub may require sign-in to download Actions artifacts. Artifacts have 90-day retention; source can recreate installers afterward.

Mac DMG SHA-256:

```text
87496d20f4e043f641b6669126262beddb6e2faec9c5c8d1310f0e7d8ab0b2ac
```

The app starts with one empty Grok Bot. Follow [Setup](SETUP.md) to choose an installed AI CLI and optionally connect your Composio project. Click the Bot’s name to select its active provider and specific model in the side panel. Enter sends; Shift+Enter adds a line break. Chat can create specialists, save memories, send requests to other Bots, and create groups. Only the active model answers for each Bot.

The application is free; provider and Composio costs/limits are separate. The Mac build is ad-hoc signed and not notarized; the Windows build is unsigned. See [Mac installation](MACOS.md) and [Windows installation](WINDOWS.md). The iOS target is source for your own Xcode signing; iPhone desktop host pairing is not implemented. Live provider inference and Composio OAuth/tool execution require user accounts and remain unverified in this implementation session.
