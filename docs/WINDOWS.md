# Windows app and Setup EXE

The Windows client uses Electron with a local HTML/CSS interface that follows the desktop screenshots. Its translucent controls use CSS materials; Apple's native Liquid Glass belongs to the SwiftUI macOS/iOS targets.

## Install

Download the `OpenGrokBot-Windows` build artifact from the draft PR's successful desktop workflow. Extract the archive and run `OpenGrokBot-0.2.0-Windows-x64-Setup.exe`. The NSIS installer supports per-user installation, choosing a destination, Start Menu/desktop shortcuts, and uninstalling.

The development installer is not Authenticode signed, so Windows reputation checks may warn. No code-signing identity is included. The installer does not replace the official Grok Bot application. Windows x64 is the packaged architecture; Arm64 has not been packaged or tested here.

## Build

On Windows with Node.js 24 and npm:

```powershell
npm ci
npm run test:desktop
node scripts/test-electron.cjs
npm run dist:windows
```

The output appears in `artifacts/windows/`. Building the NSIS installer on Linux also requires Wine; the local Linux packaging attempt stopped at that requirement. The successful installer builds run on Windows CI.

`npm run start:windows` launches the development app. `npm run preview:desktop` serves the browser preview for UI review. The browser preview stores ordinary notes in browser local storage and explicitly cannot use the Windows device vault.

## Features and security

Bot creation/search, local conversations, note persistence, export, appearance settings, the app catalog, connection status, and an encrypted device vault are included. Nothing connects to Grok Bot; all examples and new notes are local.

The installed app uses a sandboxed renderer with context isolation, no Node integration in the page, a restrictive content policy, and explicit validated IPC methods. The main process checks the calling frame. Workspace data is validated before an atomic write. External links are limited to specific documentation/project URLs. Permission requests and popup windows are denied.

Vault values use Electron `safeStorage` backed by Windows data protection. Values are encrypted before writing to disk, and vault operations fail if encryption is unavailable. There is no plaintext fallback. Item labels remain local metadata. The native Windows smoke test checks IPC, persistence after relaunch, and absence of plaintext in the vault file; it is separate from installer installation testing.

The browser UI test uses an already installed Chromium:

```bash
CHROMIUM_PATH=/path/to/chromium npm run test:ui
```

It covers persistence, creating a Bot, text escaping, failed-save recovery, app search, connection status, appearance, and reduced motion. It does not establish Windows installer behavior or live service compatibility.
