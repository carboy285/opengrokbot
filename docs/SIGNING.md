# Signed installers (optional)

Development releases are ad-hoc signed (Mac) and unsigned (Windows), so macOS asks you to right-click → Open and Windows SmartScreen warns on first run. The release workflow can sign and notarize when you add these repository secrets (GitHub → Settings → Secrets and variables → Actions), then run **Package desktop workspace** manually with **signed** checked.

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application certificate exported as .p12, base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that .p12 |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Apple ID, team ID and an app-specific password for notarization |
| `WINDOWS_CERTIFICATE_PFX_BASE64` | Code-signing certificate (.pfx), base64-encoded |
| `WINDOWS_CERTIFICATE_PASSWORD` | Password for that .pfx |

A Developer ID certificate needs a paid Apple Developer Program membership; a Windows code-signing certificate is bought from a certificate authority. Never commit these files or passwords.

## Getting the Mac secrets, step by step

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) (paid, yearly). Your **Team ID** is on the Membership page; that is `APPLE_TEAM_ID`.
2. On your Mac, open **Xcode → Settings → Accounts**, add your Apple ID, select your team and choose **Manage Certificates… → + → Developer ID Application**.
3. Open **Keychain Access**, find **Developer ID Application: Your Name (TEAMID)**, right-click it and choose **Export…**. Save it as a `.p12` file with a password. That password is `MACOS_CERTIFICATE_PASSWORD`, and the certificate's full name is `MACOS_SIGN_IDENTITY`.
4. In Terminal, turn the file into text and copy it: `base64 -i DeveloperID.p12 | pbcopy`. Paste that as `MACOS_CERTIFICATE_P12_BASE64`, then delete the `.p12` file.
5. At [account.apple.com](https://account.apple.com) → **Sign-In and Security → App-Specific Passwords**, make one named "OpenGrokBot notarization". That is `APPLE_APP_PASSWORD`; your Apple ID email is `APPLE_ID`.
6. Add all six as repository secrets, then run **Package desktop workspace** from the Actions tab with **signed** checked.

A notarized DMG opens with a normal double-click: no right-click → Open, and no "unidentified developer" warning. To confirm a build, run `spctl -a -vv /Applications/OpenGrokBot.app`; it should say **accepted** and **source=Notarized Developer ID**.
