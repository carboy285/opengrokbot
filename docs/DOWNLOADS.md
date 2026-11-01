# Development downloads · 0.5.0

Built from source commit `d23e49afedc5233b721ef7ae0d9ea692195e72af`. [Desktop tests and packaging](https://github.com/carboy285/opengrokbot/actions/runs/41267663346) passed.

| Download | Contents |
| --- | --- |
| [macOS universal installer](https://github.com/carboy285/opengrokbot/actions/runs/41267663346/artifacts/13067377768) | ZIP containing `OpenGrokBot-0.5.0-mac-universal.dmg` and SHA-256; Apple Silicon/Intel, macOS 14+ |
| [Windows x64 installer](https://github.com/carboy285/opengrokbot/actions/runs/41267663346/artifacts/13067966765) | ZIP containing `OpenGrokBot-0.5.0-Windows-x64-Setup.exe` |
| [Native Mac screenshots](https://github.com/carboy285/opengrokbot/actions/runs/41267663346/artifacts/13067668559) | Actual side panel, chat, setup, Composio, and settings captures |
| [Native Mac test results](https://github.com/carboy285/opengrokbot/actions/runs/41267663346/artifacts/13067473885) | XCTest bundles: 35 unit tests and 2 UI tests passed |
| [Xcode and Windows source](https://github.com/carboy285/opengrokbot/archive/refs/heads/codex/macos-client.zip) | Full source ZIP. Open `GrokBot.xcodeproj`; choose **GrokBot** for iOS or **GrokBotMac** for Mac |
| [Source review](https://github.com/carboy285/opengrokbot/pull/1) | Draft PR with Apple/Windows sources, packaging, tests, and setup documentation |

GitHub may require sign-in to download Actions artifacts. Artifacts have 90-day retention; source can recreate installers afterward.

Mac DMG SHA-256:

```text
58e198a99132aa4769ce7633165c31a239705239dc1989b38f1a71d09b812d23
```

The app starts with one empty Grok Bot. Follow [Setup](SETUP.md) to choose an installed AI CLI and optionally connect your Composio project. Click the Bot’s name to select its active provider and specific model in the side panel. Enter sends; Shift+Enter adds a line break. Chat can create specialists, save memories, send requests to other Bots, and create groups. Only the active model answers for each Bot.

The application is free; provider and Composio costs/limits are separate. The Mac build is ad-hoc signed and not notarized; the Windows build is unsigned. See [Mac installation](MACOS.md) and [Windows installation](WINDOWS.md). The iOS target is source for your own Xcode signing and pairs to the desktop as a controller. See [Remote access](REMOTE_ACCESS.md). The [iOS simulator workflow](https://github.com/carboy285/opengrokbot/actions/runs/41267663344) passed all 27 tests, including reconnect and host-state preservation. Physical-phone roaming and live user-account Tailscale/Funnel access remain unverified. Live provider inference and Composio OAuth/tool execution require user accounts and remain unverified in this implementation session.
