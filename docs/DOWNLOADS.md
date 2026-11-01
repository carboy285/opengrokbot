# Development downloads · 0.3.0

Built from source commit `45c9c74c75206c65a1e3db5f3726ee94ec905dd0`. [Desktop build, native tests, and packaging](https://github.com/carboy285/opengrokbot/actions/runs/41262168054) passed.

| Download | Contents |
| --- | --- |
| [macOS universal installer](https://github.com/carboy285/opengrokbot/actions/runs/41262168054/artifacts/13065493415) | ZIP containing `OpenGrokBot-0.3.0-mac-universal.dmg` and SHA-256; Apple Silicon/Intel, macOS 14+ |
| [Windows x64 installer](https://github.com/carboy285/opengrokbot/actions/runs/41262168054/artifacts/13064959179) | ZIP containing `OpenGrokBot-0.3.0-Windows-x64-Setup.exe` |
| [Native Mac screenshots](https://github.com/carboy285/opengrokbot/actions/runs/41262168054/artifacts/13065313972) | Actual workspace, chat, setup, Composio, and settings captures |
| [Native Mac test results](https://github.com/carboy285/opengrokbot/actions/runs/41262168054/artifacts/13065254344) | XCTest bundles: 22 unit tests and 2 UI tests passed |
| [Source review](https://github.com/carboy285/opengrokbot/pull/1) | Draft PR with Apple/Windows sources, packaging, tests, and setup documentation |

GitHub may require sign-in to download Actions artifacts. Artifacts have 90-day retention; the source can recreate installers afterward.

Mac DMG SHA-256:

```text
428eec8dd741ca30bafed2fc03ef908e95410c59246b7156fe292858dea4bf25
```

The app starts with one empty Grok Bot. Follow [Setup](SETUP.md) to choose an installed AI CLI and optionally connect your Composio project. The application is free; provider and Composio costs/limits are separate.

The Mac build is ad-hoc signed and not notarized; the Windows build is unsigned. See [Mac installation](MACOS.md) and [Windows installation](WINDOWS.md). The iOS target is provided as source for your own Xcode signing; iPhone desktop host pairing is not yet implemented. Live provider inference and Composio OAuth/tool execution require user accounts and remain unverified in this implementation session.
