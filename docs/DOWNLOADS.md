# Downloads · 0.7.1

[0.7.1 release](https://github.com/carboy285/opengrokbot/releases/tag/v0.7.1)

| Download | Contents |
| --- | --- |
| [Mac universal DMG](https://github.com/carboy285/opengrokbot/releases/download/v0.7.1/OpenGrokBot-0.7.1-mac-universal.dmg) | Apple Silicon and Intel; macOS 14+ |
| [Windows Setup EXE](https://github.com/carboy285/opengrokbot/releases/download/v0.7.1/OpenGrokBot-0.7.1-Windows-x64-Setup.exe) | Windows x64 |
| [iPhone Xcode project and matching sources](https://github.com/carboy285/opengrokbot/releases/download/v0.7.1/OpenGrokBot-0.7.1-Source.zip) | Open `GrokBot.xcodeproj`, choose **GrokBot**, keep your signing team/bundle ID, then run on your iPhone |
| [DMG checksum](https://github.com/carboy285/opengrokbot/releases/download/v0.7.1/OpenGrokBot-0.7.1-mac-universal.dmg.sha256) | SHA-256 |

Runtime commit: `b6edab6109d78b41b1f61c9207d89533e9bbd3ab`.
Packaging: [GitHub Actions run](https://github.com/carboy285/opengrokbot/actions/runs/41356220965).
The packaging run successfully compiled the universal Mac app and iPhone sources, built both desktop installers, and published the downloads above. No tests were run.

Update both phone and desktop to **0.7.1 (build 9)** for account-synced pins. [Changes, setup and limits](BUGFIX_0_7_1.md) · [iPhone installation](../INSTALL-IOS-0.7.1.md).

On your server computer, sign in under Settings → Computer and enable remote/phone access. On your personal computer, sign into that account, click **This computer**, select the server and approve the viewing computer on the server after comparing its fingerprint. Choose the same server on iPhone. Your local workspace stays separate; all remote AI work runs on the server.

Ask a Bot to schedule a one-time task or repeat hourly/daily/weekly. Tasks run while the desktop app is running, and missed timed runs catch up once. Incoming Bot messages are the available event trigger. View/cancel tasks in Bot details. Email, website-change and file events need separate integrations.

For cloud page reading, create a Browserbase account and enter its API key/project UUID in the **server's** Settings → Computer. Each browsing request uses an isolated temporary hosted session. No local browser is launched; cookies/logins are not retained. This provider connection has not been exercised with live credentials.

No automated tests, UI checks, database behavioral checks or physical-device validation were run, as requested. Compilation and installer packaging do not establish runtime correctness. The intermittent iPhone crash was not reproduced; this release fixes concrete crash/race paths identified in source.

Development installers: Mac ad-hoc signed and not notarized; Windows unsigned. Trusted signatures require the owner's publisher credentials.

---

## Previous release · 0.7.0

[Release notes and downloads](https://github.com/carboy285/opengrokbot/releases/tag/v0.7.0).

| Download | Contents |
| --- | --- |
| [Mac universal installer](https://github.com/carboy285/opengrokbot/releases/download/v0.7.0/OpenGrokBot-0.7.0-mac-universal.dmg) | Native Apple Silicon/Intel app; macOS 14+ |
| [Windows installer](https://github.com/carboy285/opengrokbot/releases/download/v0.7.0/OpenGrokBot-0.7.0-Windows-x64-Setup.exe) | Windows x64 Setup EXE |
| [Matching source and Xcode project](https://github.com/carboy285/opengrokbot/releases/download/v0.7.0/OpenGrokBot-0.7.0-Source.zip) | Open `GrokBot.xcodeproj`; **GrokBot** for iPhone, **GrokBotMac** for Mac; also includes Windows sources |
| [Mac DMG checksum](https://github.com/carboy285/opengrokbot/releases/download/v0.7.0/OpenGrokBot-0.7.0-mac-universal.dmg.sha256) | SHA-256 checksum; not an installer |

Runtime source commit: `4f5c16e23ce65dbe266b37a0940e5c5f89f1c0bb`. The [packaging run](https://github.com/carboy285/opengrokbot/actions/runs/41336381049) compiled the universal Mac app, created both desktop installers, and published the matching source ZIP. Unit tests, UI tests, database checks, protocol interoperability, and physical-device behavior were not tested, as requested. Compilation and installer packaging do not verify runtime behavior.

Development signatures: the Mac app is ad-hoc signed and not notarized; the Windows installer is unsigned. The release workflow supports trusted signatures after the owner configures publisher credentials. See [Desktop workspace 0.7](DESKTOP_0_7.md) for features, setup, and signing requirements.

