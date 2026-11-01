# Windows app and Setup EXE

Install the x64 Setup EXE from [Downloads](DOWNLOADS.md). It is an unsigned development build. The installer supports a per-user destination, a Start menu entry, and a desktop shortcut. It does not install AI CLIs automatically.

Follow [Setup](SETUP.md) on first launch: choose a local CLI, install/sign in using its own guide, then optionally connect a Composio project. The initial workspace contains one empty Grok Bot. Chat, saved provider sessions, stop/retry, manual Bot creation, export, appearance settings, and the device vault are implemented.

## Build

On Windows with Node.js installed:

```powershell
npm ci
npm run test:desktop
node scripts/test-electron.cjs
npm run start:windows
npm run dist:windows
```

The Setup EXE is written to `artifacts/windows/`. Windows CI runs the same unit tests, native Electron smoke test, and installer build. The smoke test launches a real fixture CLI subprocess; it does not require a paid provider account.

The renderer has no Node access and uses an allowlisted preload API. The main process validates IPC, owns the authoritative conversation state, launches CLIs without a shell, and stores encrypted credentials using Windows data protection. There is no plaintext secret fallback. Known npm command shims are resolved to package entry points; prompts use stdin or Grok Build’s private prompt file. Each Bot’s working folder is private to the application.

Composio tools reach the CLI through the bundled stdio MCP helper. Only its scoped session capability is passed to the CLI; the project key remains encrypted in app storage. Tool permission settings remain with the selected CLI. Removing Composio locally does not revoke existing grants in your Composio project.

## UI checks

```bash
CHROMIUM_PATH=/path/to/chromium npm run test:ui
```

These browser checks use an explicit test IPC fixture to exercise setup, chat rendering, persistence, draft recovery, text escaping, theme/reduced-motion behavior, and focus protection for revealed secrets. Native subprocess and encrypted-storage checks run separately on Windows. A normal browser cannot launch local CLIs and shows that limitation.

Native Apple Liquid Glass is available only on the Apple targets. Windows uses translucent styling that follows the same reference layout. Voice, file attachments, cloud-computer control, and iPhone host pairing are not implemented.
