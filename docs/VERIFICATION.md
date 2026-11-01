# Verification

The implementation workspace is Linux. Native macOS/Windows builds and iOS simulator tests run in GitHub Actions. Desktop chat uses real local CLI subprocesses; test replies come from explicit test executables, never from a production demo fallback.

## Checks

| Check | Coverage |
| --- | --- |
| Native macOS XCTest | **29 passed** in the current build: fresh single-Bot state, fixture migration, persistence, save errors, Keychain, five CLI event formats, prompt/session arguments, actual subprocess replies, executable discovery, stop behavior, Composio request contracts, private MCP configuration, model arguments, Bot creation, memory/provenance, group delivery, message limits, and real subprocess delegation using only the active provider/model |
| Native macOS UI | Cold setup, CLI selection/sign-in, optional Composio step, an empty workspace, real fixture subprocess replies, Send and Enter, Shift+Enter at the cursor, header-triggered side panel, draft preservation, model settings, Library/Computer tabs, Escape/close, Connect Apps, and Settings |
| Universal Mac packaging | Apple Silicon/Intel app and native MCP helper, code-signature verification, DMG creation/verification, SHA-256 |
| Windows unit tests | **15 passed**; tests covering workspace validation/migration, CLI events and session arguments, Composio fixed-origin requests/allowlists, capability redaction, five MCP configurations, JSON/SSE MCP replies, session headers, Bot creation/model inheritance, private/shared memory separation, message provenance, group delivery, and bounded delegation |
| Native Windows smoke | Actual Electron launch, guided setup, only one empty Bot, real fixture CLI subprocess, Unicode replies, resumed conversation, stop, isolated renderer, IPC validation, relaunch persistence, encrypted vault storage, local model catalog, exact model selection, only one active provider, chat-created specialist replies, and group chat |
| Packaged Windows MCP helper | Launches the unpacked helper through the packaged app executable with Node mode; no extra Node installation or network request |
| Browser UI | Explicit test IPC bridge: setup, Composio controls, chat rendering, local persistence, failed-save draft recovery, text escaping, side panel/model selection, Enter/Shift+Enter, theme/reduced motion, secret focus protection, and honest browser limitations |
| iOS simulator | Current source validation is running in [iOS CI](https://github.com/carboy285/opengrokbot/actions/runs/41266068807). Earlier 0.3.0 passed 16 shared model/persistence/CLI protocol and Keychain tests |
| Static/helper checks | Swift parsing and Xcode references/plists, JavaScript/shell syntax, four synthetic ASAR extraction tests |

The installed Codex 0.163.0 CLI also accepted the generated MCP command/environment configuration through `codex mcp list --json`. This was a configuration check, not a model inference request.

Source commit `b478151f50a3db637604ee088bffe993066a8ce2` passed [desktop CI](https://github.com/carboy285/opengrokbot/actions/runs/41266068805): **29 Mac unit tests, 2 Mac UI tests, 15 Windows unit tests, native Windows setup/chat/model/delegation/group/session/cancellation/encryption checks, the packaged MCP helper check, universal Mac DMG creation, and Windows NSIS creation**. Actual Mac screenshots are in `docs/screenshots/`; chat responses come from explicit test CLI executables.

The installed Codex CLI’s `app-server` model/list response was also read successfully without requesting inference. Model availability in the app follows the installed CLI/account; no catalog of guessed model names is bundled.

The [current iOS simulator workflow](https://github.com/carboy285/opengrokbot/actions/runs/41266068807) is still running. Physical-iPhone installation and desktop host pairing remain unverified/unimplemented. Earlier 0.2 preview-only results do not establish current chat/tool behavior.

## What has not been verified

- A local live Codex inference probe timed out. End-to-end provider inference requires the user’s configured account/model. Claude Code, Grok Build, OpenCode, and Gemini adapters use documented headless protocols and fixtures; live account inference has not been tested for them.
- No Composio project key was supplied. API/MCP tests use controlled HTTP/protocol fixtures; live OAuth, account linking, and tool execution are unverified.
- Mac development packages are ad-hoc signed and not notarized. Windows packages are unsigned. Neither proves a complete downloaded-install/uninstall review on a user’s machine.
- No physical iPhone was used. iPhone desktop host pairing is not implemented, so the phone target does not provide live CLI chat.
- Pixel-perfect equality with the user’s screenshots has not been established. Native CI screenshots show the actual app on the runner’s display.
- Voice, file attachments, and the proprietary Grok Bot cloud computer are not implemented. The vendor DMG was not inspected because it exceeded the attachment transfer limit; its private service protocol is separate from this local CLI implementation.

## Reproduce

```bash
python3 -m pip install -r scripts/check-requirements.txt
python3 scripts/check_project.py
python3 -m unittest discover -s scripts -p 'test_*.py' -v
npm ci
npm run test:desktop
CHROMIUM_PATH=/path/to/chromium npm run test:ui
```

On Mac, select the GrokBotMac scheme in Xcode and test, then run `./scripts/build-macos.sh`. On Windows, run `node scripts/test-electron.cjs`, `npm run dist:windows`, and `node scripts/test-packaged-helper.cjs`. Simulator results, fixture subprocesses, live provider inference, and live Composio connections are distinct checks.
