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
