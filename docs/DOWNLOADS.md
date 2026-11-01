# Development downloads

Built from source commit `c24ab6a34075604c1d6ff3bf637a8881de6cb82e`. [Desktop build, unit/UI tests, and Windows smoke test](https://github.com/carboy285/opengrokbot/actions/runs/41257537906) passed.

| Download | Contents |
| --- | --- |
| [macOS universal installer](https://github.com/carboy285/opengrokbot/actions/runs/41257537906/artifacts/13062883547) | ZIP containing `OpenGrokBot-0.2.0-mac-universal.dmg` and its checksum; Apple Silicon and Intel, macOS 14+ |
| [Windows x64 installer](https://github.com/carboy285/opengrokbot/actions/runs/41257537906/artifacts/13063094851) | ZIP containing `OpenGrokBot-0.2.0-Windows-x64-Setup.exe` |
| [Native macOS screenshots and test results](https://github.com/carboy285/opengrokbot/actions/runs/41257537906/artifacts/13063299529) | Real app-window captures and XCTest bundles |
| [Source review](https://github.com/carboy285/opengrokbot/pull/1) | Draft PR with Apple and Windows sources, packaging, tests, and setup documentation |

GitHub may require you to sign in to download Actions artifacts. These build artifacts have a 90-day retention period; the source can recreate installers afterward.

Mac DMG SHA-256:

```text
50087b3c75659d240371c7baec52d0a9aa13f6f535e50944de9da57ec90c57ad
```

The Mac installer is ad-hoc signed and not notarized. The Windows installer is unsigned. They are independent development builds with local preview workflows; neither connects to the Grok Bot service. See `MACOS.md` and `WINDOWS.md` for installation and signing details. The iOS target is included as source for Xcode signing, not a pre-signed IPA.
