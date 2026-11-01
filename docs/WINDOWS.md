# Windows app and Setup EXE

Install the x64 Setup EXE from [Downloads](DOWNLOADS.md). It is an unsigned development build. The installer supports a per-user destination, a Start menu entry, and a desktop shortcut. It does not install AI CLIs automatically.

Follow [Setup](SETUP.md) on first launch: choose a local CLI, install/sign in using its own guide, then optionally connect a Composio project. The initial workspace contains one empty Grok Bot. Chat, saved provider sessions, stop/retry, chat-based and manual Bot creation, asynchronous teamwork, groups, memory, per-Bot model selection, export, appearance settings, and the device vault are implemented.

## Build

On Windows with Node.js installed:

```powershell
npm ci
npm run test:desktop
node scripts/test-electron.cjs
npm run start:windows
npm run dist:windows
node scripts/test-packaged-helper.cjs
```

The Setup EXE is written to `artifacts/windows/`. Windows CI runs the same unit tests, native Electron smoke test, and installer build. The smoke test launches a real fixture CLI subprocess; it does not require a paid provider account.

The renderer has no Node access and uses an allowlisted preload API. The main process validates IPC, owns the authoritative conversation state, launches CLIs without a shell, and stores encrypted credentials using Windows data protection. There is no plaintext secret fallback. Known npm command shims are resolved to package entry points; prompts use stdin or Grok Build’s private prompt file. Each Bot’s working folder is private to the application.

Composio tools reach the CLI through the bundled stdio MCP helper. The helper and its API module are unpacked beside the app archive so the packaged runtime can launch them. Only its scoped session capability is passed to the CLI; the project key remains encrypted in app storage. Tool permission settings remain with the selected CLI. Removing Composio locally does not revoke existing grants in your Composio project.

## UI checks

```bash
CHROMIUM_PATH=/path/to/chromium npm run test:ui
```

These browser checks use an explicit test IPC fixture to exercise setup, chat rendering, persistence, draft recovery, text escaping, theme/reduced-motion behavior, and focus protection for revealed secrets. Native subprocess and encrypted-storage checks run separately on Windows. A normal browser cannot launch local CLIs and shows that limitation.

Native Apple Liquid Glass is available only on the Apple targets. Windows uses translucent styling that follows the same reference layout. Windows 0.7.0 uses the same [encrypted account relay as Mac/iPhone](REMOTE_ACCESS.md); sign in and approve your phone in Settings → Computer. See [Desktop workspace 0.7](DESKTOP_0_7.md). With remote access enabled, closing the window keeps the app in the system tray; Quit stops hosting. Voice, file attachment upload, remote screen sharing, power/wake management and cloud-computer control are not implemented.
