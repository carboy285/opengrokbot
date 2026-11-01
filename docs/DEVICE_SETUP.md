# Install on a physical iPhone

This installs the native iOS remote controller. AI CLIs run on your Mac or Windows host; pair the phone to that host to control the same Bots, conversations, models and running work. Physical-device installation has not been tested; simulator results are listed in [Verification](VERIFICATION.md).

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
8. Open **OpenGrokBot**. In the 0.5.0 desktop app, enable **Settings → Computer → iPhone remote control** and copy its pairing link. Open the link on the phone or paste it into **Connect Desktop**, then connect. Allow local-network access if using Wi-Fi. The host’s Bots and chats appear after authentication; no separate phone Bot is seeded. See [Remote access](REMOTE_ACCESS.md).

Apple references: [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) and [running on a device](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device).

## Verify the interface on the phone

The roster should match your desktop, starting with only Grok Bot if the host is new. Send a message and verify its reply appears on both screens. Change the active model, create a specialist, stop a response, and confirm both screens update. Disconnect the phone while a desktop task runs, then reconnect and verify work continued. Revoke the pairing key on desktop and verify the phone must pair again. No chat reply is simulated. Check VoiceOver, larger text, dark/light appearance, and reduced motion.

For unit tests select an installed iPhone simulator and choose **Product > Test**. The test target includes persistence, migration, structured CLI events, and Keychain checks. Passing simulator and contract tests is separate from physical-device signing and live Tailscale/Funnel or Wi-Fi roaming checks.
