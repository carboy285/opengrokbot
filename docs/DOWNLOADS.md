# Development downloads · Mac/iOS 0.6.0

Runtime source commit: `bcdf5c7a5d596bead5cf38d5451ee519c6f48ba5`. [Desktop build/tests](https://github.com/carboy285/opengrokbot/actions/runs/41270461498) passed: **34 Mac unit tests, 2 actual-window UI tests, universal DMG packaging, database isolation/queue checks and the existing Windows checks**.

| Download | Contents |
| --- | --- |
| [Mac universal installer](https://github.com/carboy285/opengrokbot/actions/runs/41270461498/artifacts/13069375751) | ZIP containing **`OpenGrokBot-0.6.0-mac-universal.dmg`** and SHA-256; Apple Silicon/Intel, macOS 14+ |
| [Xcode source](https://github.com/carboy285/opengrokbot/archive/refs/heads/codex/macos-client.zip) | Full repository. Open **`GrokBot.xcodeproj`**, choose **GrokBot** for iOS or **GrokBotMac** for Mac |
| [Native Mac screenshots](https://github.com/carboy285/opengrokbot/actions/runs/41270461498/artifacts/13069595125) | Actual account setup, chat, bot side panel, CLI/Composio setup and settings |
| [Mac test results](https://github.com/carboy285/opengrokbot/actions/runs/41270461498/artifacts/13069335811) | Unit and actual-window XCTest bundles |
| [Windows 0.5.0 installer](https://github.com/carboy285/opengrokbot/actions/runs/41270461498/artifacts/13068629042) | Existing Electron/NSIS app; **does not support the new iOS account connection yet** |
| [Source review](https://github.com/carboy285/opengrokbot/pull/1) | Draft PR with application, backend migration, packaging and setup documentation |

GitHub may require sign-in for Actions downloads. Artifacts have 90-day retention; the source can recreate the installers. The Mac file to open is the **`.dmg`**. The `.sha256` file is a checksum, not an installer.

Mac DMG SHA-256:

```text
cb6f2465b1c6d8c44338aa1bffe4bb2df7e61c56174d6755f9ebca80b0369435
```

## Connect your phone

Create/confirm an email account in **Mac Settings → Computer**, sign in, and turn on **Allow phone access**. Sign into the same account in the iOS app, compare its fingerprint with the Mac's phone entry, approve the phone on the Mac, and select your Mac. Supabase replaces Tailscale/pairing URLs on Apple platforms; the Mac runs all AI work. See [Remote access](REMOTE_ACCESS.md) and [iPhone installation](DEVICE_SETUP.md).

Email authentication is enabled in the connected Supabase project. Its default SMTP sends only to project-team addresses; configure custom SMTP for broader signup. Google and GitHub are deferred; their buttons appear when enabled in Supabase. Live email delivery, provider OAuth and physical-device roaming remain unverified. The final [iOS simulator run](https://github.com/carboy285/opengrokbot/actions/runs/41270461442) is being checked before source delivery.

The Mac package is ad-hoc signed and not notarized; the iPhone requires your own Xcode signing. The app is free. AI providers, Composio and Supabase/mail providers have their own quotas and plans. [Verification](VERIFICATION.md) distinguishes fixtures, native builds, deployed database checks and untested live account flows.
