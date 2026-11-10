# Downloads · 0.9.2

[Mac DMG](https://github.com/carboy285/opengrokbot/releases/download/v0.9.2/OpenGrokBot-0.9.2-mac-universal.dmg) · [Windows installer](https://github.com/carboy285/opengrokbot/releases/download/v0.9.2/OpenGrokBot-0.9.2-Windows-x64-Setup.exe) · [Matching iPhone/Xcode sources](https://github.com/carboy285/opengrokbot/releases/download/v0.9.2/OpenGrokBot-0.9.2-Source.zip)

Real Grokbot parity: voice capture with waveform, live typing/thinking animation, Grok personality when Grok provider is active, unified Computer (Terminal + Browser + Files) with image thumbnails, and pixel-perfect dark glass — built from `0.9.2` (build 13). All 0.7.x features retained.

> **Build note for 9.2:** Mac DMG + Windows EXE + Source.zip are produced by `.github/workflows/release-desktop.yml` on macOS-26 / windows-latest runners. Dispatch via GitHub Actions → *Package desktop workspace* → Run workflow (signed=false for dev ad-hoc). Publishing uploads 3+ files and creates `v{VERSION}` release automatically.

Runtime commit: `arena/69875ce0`. [Packaging run](https://github.com/carboy285/opengrokbot/actions). Unified Computer pane, file preview, and Grok persona now match the 0.78.1 product design while keeping the local-CLI security model (no cloud Grok credentials collected).

[Install matching iPhone sources](../INSTALL-IOS-0.7.3.md). Mac ad-hoc signed, Windows unsigned.

---

## Previous release · 0.7.3

[Mac DMG](https://github.com/carboy285/opengrokbot/releases/download/v0.7.3/OpenGrokBot-0.7.3-mac-universal.dmg) · [Windows installer](https://github.com/carboy285/opengrokbot/releases/download/v0.7.3/OpenGrokBot-0.7.3-Windows-x64-Setup.exe) · [Matching iPhone/Xcode sources](https://github.com/carboy285/opengrokbot/releases/download/v0.7.3/OpenGrokBot-0.7.3-Source.zip)

Hides the Mac sidebar’s pinned-Bot horizontal scrollbar even when macOS is set to always show scrollbars. Sideways scrolling remains available. Version 0.7.3, build 11; all 0.7.2 features are retained.

Runtime commit: `506f3a58b45d8dfc62fe17c2ad6e84bc13b3e7a1`. [Packaging run](https://github.com/carboy285/opengrokbot/actions/runs/41360400774).
Packaging completed successfully: the universal Mac app and iPhone sources compiled, both desktop installers were packaged, and the release was published. No automated tests were run.

[Install matching iPhone sources](../INSTALL-IOS-0.7.3.md). No automated tests or physical-device validation were run, as requested. Mac remains ad-hoc signed/not notarized; Windows remains unsigned.

---

## Previous release · 0.7.2

[Release and downloads](https://github.com/carboy285/opengrokbot/releases/tag/v0.7.2)

| Download | Contents |
| --- | --- |
| [Mac universal DMG](https://github.com/carboy285/opengrokbot/releases/download/v0.7.2/OpenGrokBot-0.7.2-mac-universal.dmg) | Apple Silicon and Intel; macOS 14+ |
| [Windows Setup EXE](https://github.com/carboy285/opengrokbot/releases/download/v0.7.2/OpenGrokBot-0.7.2-Windows-x64-Setup.exe) | Windows x64 |
| [Matching iPhone Xcode project and sources](https://github.com/carboy285/opengrokbot/releases/download/v0.7.2/OpenGrokBot-0.7.2-Source.zip) | Open GrokBot.xcodeproj; select GrokBot for iPhone |
| [Mac checksum](https://github.com/carboy285/opengrokbot/releases/download/v0.7.2/OpenGrokBot-0.7.2-mac-universal.dmg.sha256) | SHA-256 |

Runtime commit: `ca2fb49eb97a41bdecf6cafdbad241231fecd55f`. [Packaging run](https://github.com/carboy285/opengrokbot/actions/runs/41359536522).
The packaging run successfully compiled the iPhone sources and universal Mac app, built the Mac/Windows installers, and published the downloads above. No automated tests were run.

Quit older copies and update the **hosting computer and viewing devices** to **0.7.2 (build 10)**. Enable Allow phone access on the host. Select the host through **This computer** on Windows or **Connect Desktop** on iPhone; compare fingerprints and approve the viewing device on the host. Windows includes **Reconnect**. The phone views desktop Bots; it does not host Bots for a PC.

Unpinned Bots now sort by recent chat use and messages; pinned order stays in place. Each Bot has its own visible **local browser** with persistent cookie/login storage. No Browserbase account is needed. Approved Mac, Windows and iPhone viewers can watch browser and VM images refresh roughly every three seconds. Use Browser / VM view after selecting the host. These views do not send keyboard/mouse input. On a hosting Mac, enable per-Bot VM viewing and grant macOS Screen Recording access.

Bot details also includes **Linux VM** setup. Download/install UTM on Mac or VirtualBox 7.2+ on Windows through the provided links, then select a Linux guest asset: a matching-architecture `.utm` template on Mac, or an Ubuntu 24.04 ISO/Linux OVA on Windows. The app imports/provisions a per-Bot VM and opens its local console. Optional guest commands require guest tools and the owner's enable switch; the AI CLI remains on the host.

[Remote loading fixes, browser/VM setup and limits](REMOTE_0_7_2.md) · [iPhone installation](../INSTALL-IOS-0.7.2.md).

No automated tests or physical-device validation were run, as requested. Existing relay logs were inspected; compilation and installer packaging do not confirm runtime interoperability. The reported hang was not reproduced locally. Development installers remain Mac ad-hoc signed/not notarized and Windows unsigned.

---

## Previous release · 0.7.1

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

