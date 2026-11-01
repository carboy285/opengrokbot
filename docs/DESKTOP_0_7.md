# Desktop workspace · 0.7.0

## What changed

- **Windows/iPhone compatibility:** Windows uses the same account discovery and encrypted mailbox contract as Mac/iPhone. In Windows Settings → Computer, sign in, compare the phone fingerprint, and approve the phone. Tokens, private device keys, and local approvals are encrypted through Windows device storage. The old HTTP pairing host is no longer started or restored.
- **Connection reliability:** ready, connecting, waiting-for-approval, offline/retrying, and disabled states; reconnect controls; bounded retry backoff; last-contact timestamps; copyable diagnostics that omit accounts, tokens, keys, chats, and pairing secrets.
- **Bot organization:** persistent pins, folder assignment, sidebar folder filtering, drag ordering, and avatar customization on both desktops. Avatars travel in encrypted workspace snapshots to iPhone. iPhone pins remain local to that phone; desktop pins/folders live in the desktop workspace.
- **Chat delivery:** Windows renders a pending message immediately, keeps failed sends available for retry with the same request ID, and deduplicates accepted delivery IDs in the main process. Streamed replies update existing message elements and preserve the text box and scroll position. Mac shows local acceptance and actionable send errors. Both desktop apps recover drafts after reopening.
- **Provider setup:** installed CLI discovery, honest readiness feedback (Codex login status is directly queried; other providers are verified when they actually send a message), per-provider success/failure state, and setup actions beside failed responses. Credentials remain with each CLI.
- **Workspace design:** consistent vector avatars, pinned sections, folder selectors, stable conversation rendering, keyboard focus outlines, and keyboard Bot switching. Use Command/Ctrl+K to find a Bot; Mac also supports Command+Shift+[ / ] to cycle Bots.
- **Updates:** both desktops check official GitHub releases, notify about newer versions, and open the release download page. Mac has a daily notification preference. Windows checks once daily while the app is open. Downloads are manual; no installer is silently executed.

## Upgrade

Install the new desktop build over the existing installation. Keep your existing app identity and data directories. Saved conversations, Bots, provider sessions, Composio configuration, and vault notes are retained. Windows users moving from 0.5 must sign in and approve their phones again; old pairing links are not imported. If you previously configured a Tailscale Serve/Funnel route, remove that specific old app route yourself. This version does not modify unrelated routes.

Use Settings → Computer for phone access and Settings → Updates for downloads. Keep the host awake with the app running. Windows stays in its tray when phone access is on; the tray’s Quit action stops hosting and running AI work.

Drafts are stored with local workspace data. Account credentials and device keys use Keychain on Mac and OS-protected encrypted storage on Windows. Drafts and chats are not included in copied connection diagnostics.

## Packaging and trusted signatures

The **Package desktop workspace** workflow compiles and packages installers without running tests. Pushes to `feature/desktop-workspace` produce a clearly labeled development release: an ad-hoc-signed, non-notarized Mac DMG and an unsigned Windows installer. The same workflow can be run manually with **signed** enabled to require trusted signatures. It fails early rather than silently falling back when credentials are absent.

Configure these GitHub repository secrets before requesting a signed run:

| Platform | Required secrets |
| --- | --- |
| Mac | `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGN_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` |
| Windows | `WINDOWS_CERTIFICATE_PFX_BASE64`, `WINDOWS_CERTIFICATE_PASSWORD` |

The Apple certificate must be a Developer ID Application identity with its private key. Windows needs a valid code-signing certificate/private key supported by electron-builder. Password-protected certificate bundles are loaded only on the build runner. Apple notarization uses a temporary keychain profile. Certificates and private keys are not packaged with the app. Signed releases use a new version rather than replacing an already published development release.

## Verification status

The [0.7.0 packaging run](https://github.com/carboy285/opengrokbot/actions/runs/41336381049) successfully compiled the universal Mac app and built both desktop installers from runtime commit `4f5c16e23ce65dbe266b37a0940e5c5f89f1c0bb`. No unit tests, UI tests, browser checks, database queries, protocol interoperability checks, or physical-device validation were run for this change, as requested. Installer compilation/packaging does not establish runtime correctness. Windows/iPhone interoperability and new UI behavior require device validation. Signing cannot be completed without the owner’s publisher credentials.
