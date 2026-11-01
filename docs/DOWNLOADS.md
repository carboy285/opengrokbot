# Downloads · 0.7.0

[Release notes and downloads](https://github.com/carboy285/opengrokbot/releases/tag/v0.7.0).

| Download | Contents |
| --- | --- |
| [Mac universal installer](https://github.com/carboy285/opengrokbot/releases/download/v0.7.0/OpenGrokBot-0.7.0-mac-universal.dmg) | Native Apple Silicon/Intel app; macOS 14+ |
| [Windows installer](https://github.com/carboy285/opengrokbot/releases/download/v0.7.0/OpenGrokBot-0.7.0-Windows-x64-Setup.exe) | Windows x64 Setup EXE |
| [Matching source and Xcode project](https://github.com/carboy285/opengrokbot/releases/download/v0.7.0/OpenGrokBot-0.7.0-Source.zip) | Open `GrokBot.xcodeproj`; **GrokBot** for iPhone, **GrokBotMac** for Mac; also includes Windows sources |
| [Mac DMG checksum](https://github.com/carboy285/opengrokbot/releases/download/v0.7.0/OpenGrokBot-0.7.0-mac-universal.dmg.sha256) | SHA-256 checksum; not an installer |

Runtime source commit: `4f5c16e23ce65dbe266b37a0940e5c5f89f1c0bb`. The [packaging run](https://github.com/carboy285/opengrokbot/actions/runs/41336381049) compiled the universal Mac app, created both desktop installers, and published the matching source ZIP. Unit tests, UI tests, database checks, protocol interoperability, and physical-device behavior were not tested, as requested. Compilation and installer packaging do not verify runtime behavior.

Development signatures: the Mac app is ad-hoc signed and not notarized; the Windows installer is unsigned. The release workflow supports trusted signatures after the owner configures publisher credentials. See [Desktop workspace 0.7](DESKTOP_0_7.md) for features, setup, and signing requirements.

## Latest desktop and iPhone source

[Download the latest source/Xcode project](https://github.com/carboy285/opengrokbot/archive/refs/heads/codex/macos-client.zip) for **0.7.0 (build 8)**. See [Desktop workspace 0.7](DESKTOP_0_7.md) for the Mac/Windows changes, phone connection setup, signing requirements, and verification limits.

Windows now implements the account relay used by iPhone and Mac. Both desktops include persistent Bot pins/folders, drag ordering, avatar customization, draft recovery, better provider feedback, and update notifications. The iPhone retains the redesigned chat and roster, avatar-colored controls, corrected tap targets, and lower composer.

For iPhone, open `GrokBot.xcodeproj`, choose **GrokBot** and your iPhone, keep your existing signing team and bundle identifier, and choose **Product → Run**. Confirm **Settings → App version: 0.7.0** afterward. For Mac, choose **GrokBotMac**; for Windows, use the desktop installer or build with `npm ci` and `npm run dist:windows`.

Unit, UI, database, protocol-interoperability, and physical-device checks have not been run for this update, at the user's request. Build/package results will be recorded with published downloads. Trusted installer signing requires the owner’s certificates and credentials; development builds are labeled accordingly.

## Previous Apple release · 0.6.1

[Release and downloads](https://github.com/carboy285/opengrokbot/releases/tag/v0.6.1).

| Download | Contents |
| --- | --- |
| [Mac universal installer](https://github.com/carboy285/opengrokbot/releases/download/v0.6.1/OpenGrokBot-0.6.1-mac-universal.dmg) | `OpenGrokBot-0.6.1-mac-universal.dmg`; Apple Silicon/Intel, macOS 14+ |
| [Matching Xcode source ZIP](https://github.com/carboy285/opengrokbot/releases/download/v0.6.1/OpenGrokBot-0.6.1-Xcode.zip) | Complete repository. Open `GrokBot.xcodeproj`, choose **GrokBot** for iPhone or **GrokBotMac** for Mac |
| [DMG checksum](https://github.com/carboy285/opengrokbot/releases/download/v0.6.1/OpenGrokBot-0.6.1-mac-universal.dmg.sha256) | SHA-256 checksum; this file is not an installer |

## This update

- The phone finds the available Mac even when older offline installations remain registered. An available saved Mac is preferred.
- Phone access starts on Mac sign-in unless previously turned off. The Mac prompts for approval when a new phone requests access; iOS displays the phone fingerprint and approval instructions until approved.
- The Mac refreshes its device list before handling a newly registered phone's first request.
- Click a Bot's avatar in its Mac side panel, or tap it in iPhone Bot details, to select a shape/color, generate a random look, upload an image, or reset it. Save the avatar to update both devices.

Install the new Mac DMG and rebuild the iPhone app from the matching ZIP. In Xcode, select your signing team and physical iPhone, then run the **GrokBot** scheme. Sign into the same account on both devices, compare the phone fingerprint, and approve it on the Mac. Keep the Mac awake with OpenGrokBot running. If **Allow phone access** was previously turned off, enable it in **Mac Settings → Computer**.

See [iPhone installation](DEVICE_SETUP.md) and [Remote access](REMOTE_ACCESS.md).

## Build status

Runtime source commit: `49304b6967685bcdf392dc2cac37d421dc21b3ac`. [Packaging run](https://github.com/carboy285/opengrokbot/actions/runs/41318915250) compiled the universal Mac app and packaged the DMG and matching source archive. Tests and additional checks were skipped at the user's request. Physical Mac/iPhone behavior remains unverified for this update; previous test results in [Verification](VERIFICATION.md) apply to the earlier version.

The Mac package is ad-hoc signed and not notarized; the iPhone requires your own Xcode signing. The app is free. AI providers, Composio, Supabase, and mail providers have their own quotas and plans.
