# Install on a physical iPhone

This installs the independent app’s offline workflows. Live Grok Bot access remains unavailable. These steps have not been exercised on a physical device in this session. The iOS simulator build and all nine unit tests passed in CI.

## Prerequisites

- A Mac with Xcode 16 or later and an iOS SDK that supports your phone's OS version. Newer iOS versions may require a newer Xcode.
- An iPhone on iOS 18 or later, a USB cable, and your Apple ID.
- The complete repository, including `GrokBot.xcodeproj`, sources, and resources.

## Signing and Developer Mode

1. Launch Xcode once, accept its license, and install the requested platform components.
2. Open **Xcode > Settings > Accounts** and add your Apple ID. A personal team can generally install a development build on your own device; free signing has limits and may require periodic re-signing. A paid Apple Developer membership is required for distribution workflows such as TestFlight. Consult Apple's current account terms.
3. Open `GrokBot.xcodeproj`. Select the **GrokBot** target, then **Signing & Capabilities**. Enable **Automatically manage signing**, select your team, and change `org.opengrokbot.ios` to a unique identifier you control, such as `com.yourname.opengrokbot`. Do not add secrets to build settings. Set the test target's team and bundle identifier too if running device tests.
4. Connect the unlocked iPhone by USB. Choose **Trust This Computer** on the phone and enter its passcode if asked. Open **Window > Devices and Simulators** in Xcode and wait for pairing and device preparation.
5. On the phone, open **Settings > Privacy & Security > Developer Mode**, enable it, and restart when prompted. After restart, unlock the phone and confirm **Turn On**. The setting may appear only after Xcode has paired with the phone.
6. In Xcode, select the **GrokBot** scheme and your physical iPhone as the run destination. Choose **Product > Run** (Command-R). Resolve any signing errors using Xcode's team/profile controls.
7. If iOS asks you to trust your developer identity, review the profile in **Settings > General > VPN & Device Management** and trust your own development identity. Keep the phone unlocked while Xcode installs and launches the build.
8. Open **OpenGrokBot**, read its integration status, and choose **Explore offline preview**. Create a preview Bot and save a local note. Close and reopen the app to check persistence. Open Settings to change appearance or leave preview.

Apple references: [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) and [running on a device](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device).

## Verify this foundation on the phone

- Offline labels appear on the roster and in every conversation.
- Saving a note produces only a local user entry and no invented Bot response.
- Notes survive relaunch; empty input cannot be saved.
- VoiceOver identifies buttons; larger text remains readable; the keyboard leaves the composer accessible.
- Leaving preview retains notes; resetting asks for confirmation and replaces preview data.
- The Integration screen says **Not connected** even after saving a valid HTTPS origin draft.
- No login prompt or permission request appears for microphone, camera, photos, local network, or notifications, because those workflows are not implemented.

For unit tests select an installed iPhone simulator and choose **Product > Test** (Command-U). The test target includes Keychain checks in the app host. Passing those tests is separate from validating live integration.

## Network setup for eventual integration

There is no server to configure for this foundation. A Mac installer cannot run directly on iOS. The documented Grok Bot product uses its own cloud computers; no independently usable host port or authentication registration has been verified.

If a supported independent transport is recovered, its host must be reachable from the phone and use valid HTTPS certificates. A phone's `localhost` is the phone itself, not the Mac. A future LAN path may require a documented local-network usage description and permission; a VPN path must preserve service authentication. Never disable TLS validation, grant broad ATS exceptions, or expose an unauthenticated bridge to make a test pass.

If your aim is to use the service immediately, the vendor's [official mobile guide](https://docs.x.ai/grok-bot/mobile) documents its current iPhone app. Installing that app does not supply this independent project's missing protocol implementation.
