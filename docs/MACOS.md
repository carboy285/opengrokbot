# Native macOS application and DMG

The macOS app is the current priority. It is a native SwiftUI/AppKit application with a universal Apple Silicon/Intel build target. The reference screenshots guide the dark sidebar, Bot avatars, centered header, message bubbles, bottom composer, Connect Apps catalog, and settings layout.

## Run from Xcode

1. Open `GrokBot.xcodeproj` on a Mac.
2. Select the **GrokBotMac** scheme and **My Mac**.
3. Use Xcode 26 or later for Apple's Liquid Glass APIs. The app supports macOS 14 and later; macOS 26 activates Liquid Glass, while earlier systems use native materials.
4. For local development, choose **Sign to Run Locally** or your development team in Signing & Capabilities.
5. Choose **Product > Run**. The local preview opens directly in the desktop workspace.

The first successful CI build used Xcode 26.3 and produced a universal DMG after nine native unit tests passed. Later CI also runs actual window captures using a macOS UI test target. See `VERIFICATION.md` for the latest status.

## Install a built DMG

Open `OpenGrokBot-0.2.0-mac-universal.dmg` and drag **OpenGrokBot** to **Applications**. The image also contains an Applications shortcut and a Read Me. Launch your installed copy from Applications.

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

## Working local features

- Bot sidebar, search, keyboard navigation, and per-Bot conversations.
- Preview Bot creation and confirmed deletion.
- Local notes saved atomically, with drafts preserved on save failure.
- Conversation export through the macOS save panel.
- App catalog search and categories. Connect actions explain the missing live session rather than pretending to authorize an app.
- Settings sections for General, Computer, Permissions, Vault, Usage & Billing, and Updates. Unavailable cloud features show their actual status.
- Device vault: labeled secure notes stored in macOS Keychain, with reveal/hide and confirmed deletion. Revealed values and the secret entry field clear when the app loses focus. Bot service accounts cannot read this vault.
- Dark, light, and system appearance; system fonts; native glass/material controls; Reduce Motion and Reduce Transparency handling.

Keyboard shortcuts: **⌘N** creates a preview Bot, **⌘F** opens Bot search, **⌘,** opens Settings, **⌘Return** saves a local note, **⇧⌘E** exports a conversation, and **Escape** closes a panel. Context-click a Bot for export or deletion.

## Service status

This is an independent app with working local features. It still cannot authenticate with or operate the actual Grok Bot service. Example Bot messages and handoffs are fixtures; all new notes stay local. No connector, approval, computer, billing, model, or run operation is sent upstream. The missing binary/protocol evidence is listed in `HARNESS.md`.

The optional local vault is separate from the product's cloud Vault. Secret values stay in Keychain; only item IDs and labels are indexed in app-owned preferences. Profile display names are local preferences, not account identities. No subscription usage is invented.
