# Native macOS application and DMG

The macOS app is the current priority. It is a native SwiftUI/AppKit application with a universal Apple Silicon/Intel build target. The reference screenshots guide the dark sidebar, Bot avatars, centered header, message bubbles, bottom composer, Composio Connect Apps, and settings layout.

## Run from Xcode

1. Open `GrokBot.xcodeproj` on a Mac.
2. Select the **GrokBotMac** scheme and **My Mac**.
3. Use Xcode 26 or later for Apple's Liquid Glass APIs. The app supports macOS 14 and later; macOS 26 activates Liquid Glass, while earlier systems use native materials.
4. For local development, choose **Sign to Run Locally** or your development team in Signing & Capabilities.
5. Choose **Product > Run**. The guided setup opens. Choose an installed CLI, sign in through it, and optionally connect a Composio project.

Native CI compiles the app and helper, runs unit/UI tests, and packages a universal DMG. See `VERIFICATION.md` for the latest status.

## Install a built DMG

Open `OpenGrokBot-0.3.0-mac-universal.dmg` and drag **OpenGrokBot** to **Applications**. The image also contains an Applications shortcut and a Read Me. Launch your installed copy from Applications.

The CI package is ad-hoc signed and **not notarized**. macOS may block a downloaded copy under Gatekeeper. A local Xcode build is the predictable development path; a public distribution build requires a Developer ID certificate and Apple notarization. Do not disable Gatekeeper globally. The package does not replace, modify, or launch the official Grok Bot app.

## Build the installer yourself

From Terminal in this repository on a Mac:

```bash
./scripts/build-macos.sh
```

The script builds both `arm64` and `x86_64`, verifies the code signature, copies the app into a staging folder, creates a compressed disk image with `hdiutil`, verifies the image, and writes a SHA-256 checksum. It refuses to overwrite an existing output image. Outputs go to `artifacts/macos/`.

For distribution, select a Developer ID identity already installed in your Mac's Keychain. Provision notarization credentials with Apple's `notarytool store-credentials` on your own Mac, then provide only their local profile name:

```bash
MACOS_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
MACOS_NOTARY_PROFILE='your-existing-notary-profile' \
./scripts/build-macos.sh /absolute/path/to/new-output-folder
```

No Apple credentials are included, requested in source, or available to this project's CI. Successful ad-hoc signature verification is separate from notarization and Gatekeeper acceptance.


## Local CLI execution and tools

See [SETUP.md](SETUP.md) for the full walkthrough. Codex, Claude Code, Grok Build, OpenCode, and Gemini CLI run as local subprocesses. The app is outside App Sandbox to access host installations; each Bot has an app-owned working folder. CLI credentials remain with the provider CLI. Composio project credentials are stored in Keychain, and a native `ComposioBridge` executable in `Contents/Helpers` supplies MCP transport.

Conversations are stored under `~/Library/Application Support/OpenGrokBot/`. Prior sandbox preview data is copied from the app container on first migration, with a backup retained. Normal conversation files are not a secret vault.

The app starts with one empty Grok Bot. Extra Bots are created only by the user. Voice, file attachments, the proprietary Grok Bot cloud computer, and an iPhone host bridge are not implemented.
