# OpenGrokBot for iPhone

Native SwiftUI foundation for an independent Grok Bot client. MIT licensed, with an Xcode project, local preview workspace, inspection tools, and tests.

**This build cannot connect to or operate Grok Bot. No harness version is verified compatible.** The supplied `Grok_Bot_0.78.1.dmg` could not be transferred into this environment because the file tool limits transfers to 32 MiB. No bytes from that installer were inspected. The real integration requested remains unfinished.

The screenshots establish the design reference. Official product documentation establishes persistent Bots, cloud computers, Cursor browser sign-in, and synced mobile conversations. It does not establish the client protocol needed to implement this app. See [evidence and integration status](docs/HARNESS.md) for sources and unknowns. This project includes no reconstructed vendor code and no private endpoints. Grok Build and the Grok model API are not substitutes for the Grok Bot product.

## Open and run

Requirements: a Mac with Xcode 16 or newer, an installed iOS 18+ SDK, an Apple ID for device signing, and an iPhone running iOS 18 or newer. Python 3.9+ is needed only for installer inspection. The app has no third-party runtime dependencies and requires no API key.

1. Open `GrokBot.xcodeproj` in Xcode and select the **GrokBot** scheme.
2. For a simulator, select an iPhone simulator running iOS 18+ and choose **Product > Run**.
3. Tap **Explore offline preview**. Create preview Bots with **+**, search, and save local notes in a conversation.

For a physical phone, follow the [complete device installation steps](docs/DEVICE_SETUP.md). No website, backend, or account configuration is needed to run the offline foundation. Signing and installing it does not enable Grok Bot service access.

## Included workflows

| Screen | Behavior in this build |
| --- | --- |
| Welcome | Explains integration status and opens offline preview |
| Bot roster | Searches local preview Bots; opens conversations; swipe deletes a preview Bot |
| Conversation | Displays labeled example messages and an example handoff; saves local notes; shares text through the system share sheet |
| Create preview Bot | Saves a name, description, and color locally |
| Settings | Dark/light/system appearance; leave preview; confirm reset of preview data |
| Integration | Shows verified facts and missing protocol evidence; validates and saves an optional future HTTPS origin draft without contacting it |

There are no real runs, agent responses, tool calls, approvals, artifacts, connector management, Vault, account login, notifications, voice, computer access, or streaming. Example messages are fixtures. Saving a note never produces an automated reply. Offline labels remain visible throughout the preview. Preview data is separate from any future integration, and is never uploaded.

## Architecture and choices

SwiftUI and iOS 18 match the official mobile product's documented minimum and provide native navigation, Dynamic Type, VoiceOver labels, materials, and keyboard behavior. No external dependency is needed to build the app. The deployment target is a choice for this foundation, not a claim of service compatibility.

- `App/` owns the application and main-actor preview state. Changes persist atomically before the UI commits them, preserving the draft when saving fails.
- `Core/` contains local models, JSON persistence, HTTPS origin-draft validation, and the integration boundary. `UnverifiedHarnessClient` always throws before attempting a connection. Its capability report never claims a supported version.
- `Features/` contains roster, conversations, creation, settings, and integration status.
- `Design/` contains adaptive colors, native controls, and original vector Bot avatars.
- `Security/` provides a Keychain store for a future verified credential flow; it is not currently used to collect or provision tokens.
- `Resources/` contains an original app icon, Info.plist, and a privacy manifest for app-owned UserDefaults access.

No reconnect or background-execution behavior is implemented because no transport exists. Local edits save immediately; background suspension cannot be mistaken for a running cloud task. A future authenticated client must handle foreground refresh, cancellation, expired credentials, event resumption, and version negotiation according to the inspected protocol.

## Inspect your installer

On your Mac, from the repository directory:

```bash
./scripts/inspect-dmg.sh "$HOME/Downloads/Grok_Bot_0.78.1.dmg" inspection/0.78.1
```

This mounts the installer read-only, records its checksum and selected bundle metadata, captures signing diagnostics, and extracts standard Electron `app.asar` contents without launching the application. Outputs are local and gitignored. It never reads your installed app's account storage or Keychain. See [binary inspection](docs/BINARY_INSPECTION.md) for limitations and the evidence needed to implement the protocol.

If the DMG uses another layout or the archive contains unsupported entries, the tool stops rather than guessing. The extractor can also operate on a smaller copied `app.asar` directly. The macOS wrapper has not been run against the supplied DMG here; synthetic ASAR tests passed.

## Network, authentication, and security

There is no verified backend or bridge setup to configure. Do not expose a desktop port or use a generic Grok API key expecting this app to control your Bots. Official browser login documentation does not establish OAuth client registration, redirects, scopes, or token lifecycle for an independent iOS app.

The iOS foundation makes no network requests. External documentation links open in the system browser. It contains no ATS exemptions, custom trust bypass, analytics, or embedded credentials. A saved future origin is only a local draft and rejects credentials, paths, queries, fragments, plaintext HTTP, and common loopback addresses. Do not put secrets in it.

The unused Keychain implementation stores credentials as `WhenUnlockedThisDeviceOnly`, without iCloud synchronization, for eventual use after the real authentication flow is verified. Secrets must never enter UserDefaults, project files, logs, or screenshots. Preview notes are ordinary app data in Application Support, written atomically with complete file protection; they may be included in normal device backups and are not a secret vault.

A future self-hosted bridge would require a verified upstream protocol, authenticated access, and a trusted HTTPS hostname reachable by the phone. `localhost` on a physical iPhone refers to that phone. VPN reachability alone does not authenticate a service. No bridge is supplied because its upstream protocol is unknown. Do not run a Mac DMG as an iPhone executable.

## Checks and tests

Local Linux checks:

```bash
python3 -m pip install -r scripts/check-requirements.txt
python3 scripts/check_project.py
python3 -m unittest discover -s scripts -p 'test_*.py' -v
bash -n scripts/inspect-dmg.sh
```

On a Mac:

```bash
xcodebuild -project GrokBot.xcodeproj -scheme GrokBot \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project GrokBot.xcodeproj -scheme GrokBot -showdestinations
# Replace the example destination with an installed iPhone simulator from the list.
xcodebuild -project GrokBot.xcodeproj -scheme GrokBot \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test
```

XCTest covers origin validation, unsupported connection behavior, persistence, preview state changes, save failure, and Keychain replacement/deletion. The included GitHub workflow can run these on macOS after the project is pushed. **That workflow has not run in this session.**

See [verification results](docs/VERIFICATION.md) for the exact checks completed. Swift syntax parsing is not type checking or compilation. No Xcode build, simulator UI review, XCTest run, signing, physical device install, or live service operation was verified here.

## Costs, limits, and license

The offline app incurs no model/API charges and makes no service calls. Grok Bot service access requires an eligible paid plan according to the [official mobile requirements](https://docs.x.ai/grok-bot/mobile). No third-party API pricing, rate limits, or compatibility commitments have been verified. Apple signing and distribution rules apply separately; see the device guide.

The original code and artwork in this repository are MIT licensed; see [LICENSE](LICENSE). Grok Bot, xAI, and Cursor names identify the intended integration. This project is not affiliated with or endorsed by those organizations. Their binaries and artwork are not redistributed.
