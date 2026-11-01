# Development downloads

## Latest iPhone layout source

[Download the latest Xcode project](https://github.com/carboy285/opengrokbot/archive/refs/heads/codex/macos-client.zip) for **0.6.2 (build 3)**. This source update includes pinned Bot tiles, a floating search bar, glass navigation controls, rounded avatars and chat bubbles, and shorter connection polling waits. Open `GrokBot.xcodeproj`, select the **GrokBot** scheme and your iPhone, then choose **Product → Run** to replace the installed app. In the iPhone app, open **Settings** and confirm that **App version** shows **0.6.2**. Unzipping the project alone does not update the installed app.

Long-press any Bot to **Pin to top** or **Unpin Bot**, or use the button in Bot details. Pins are saved on this iPhone separately for each account and Mac. Pinned tiles have no arrows and open Bot details. Unpinned rows have arrows and open conversations. The main assistant is initially pinned. The phone remembers its Mac for a direct reconnect; the new Mac source also polls more frequently while the phone is active. Update both apps from this project for all latency changes.

Version 0.6.2 has not been compiled or tested at the user's request. Connection latency and appearance on a physical phone remain unverified. The versioned 0.6.1 DMG and ZIP below predate this update.

## Published Apple downloads

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
