# Verification

The implementation workspace is Linux. Native macOS/Windows builds and iOS simulator tests run in GitHub Actions. Desktop chat uses real local CLI subprocesses; test replies come from explicit test executables, never from a production demo fallback.

## Checks

| Check | Coverage |
| --- | --- |
| Native macOS XCTest | **35 passed** in the current build: fresh single-Bot state, fixture migration, persistence, save errors, Keychain, five CLI event formats, prompt/session arguments, actual subprocess replies, executable discovery, stop behavior, Composio request contracts, private MCP configuration, model arguments, Bot creation, memory/provenance, group delivery, message limits, real subprocess delegation using only the active provider/model, actual controller-to-host HTTP, state snapshots, exact-once send IDs, pairing revocation, and Tailscale route preservation |
| Native macOS UI | Cold setup, CLI selection/sign-in, optional Composio step, an empty workspace, real fixture subprocess replies, Send and Enter, Shift+Enter at the cursor, header-triggered side panel, draft preservation, model settings, Library/Computer tabs, Escape/close, Connect Apps, and Settings |
| Universal Mac packaging | Apple Silicon/Intel app and native MCP helper, code-signature verification, DMG creation/verification, SHA-256 |
| Windows unit tests | **18 passed**; tests covering workspace validation/migration, CLI events and session arguments, Composio fixed-origin requests/allowlists, capability redaction, five MCP configurations, JSON/SSE MCP replies, session headers, Bot creation/model inheritance, private/shared memory separation, message provenance, group delivery, bounded delegation, real HTTP authentication/revocation, polling, request limits, and Tailscale route ownership |
| Native Windows smoke | Actual Electron launch, guided setup, only one empty Bot, real fixture CLI subprocess, Unicode replies, resumed conversation, stop, isolated renderer, IPC validation, relaunch persistence, encrypted vault storage, local model catalog, exact model selection, only one active provider, chat-created specialist replies, group chat, and remote HTTP control while the window is hidden in the system tray |
| Packaged Windows MCP helper | Launches the unpacked helper through the packaged app executable with Node mode; no extra Node installation or network request |
| Browser UI | Explicit test IPC bridge: setup, Composio controls, chat rendering, local persistence, failed-save draft recovery, text escaping, side panel/model selection, Enter/Shift+Enter, theme/reduced motion, secret focus protection, and honest browser limitations |
| iOS simulator | **27 passed** in [iOS CI](https://github.com/carboy285/opengrokbot/actions/runs/41267663344): shared model, persistence, CLI protocol, Keychain, HTTP/pairing contracts and controller lifecycle; a fixture host verifies send, reconnect and disconnect without saving an independent phone workspace |
| Static/helper checks | Swift parsing and Xcode references/plists, JavaScript/shell syntax, four synthetic ASAR extraction tests |

The installed Codex 0.163.0 CLI also accepted the generated MCP command/environment configuration through `codex mcp list --json`. This was a configuration check, not a model inference request.

Source commit `d23e49afedc5233b721ef7ae0d9ea692195e72af` passed [desktop CI](https://github.com/carboy285/opengrokbot/actions/runs/41267663346): **35 Mac unit tests, 2 Mac UI tests, 18 Windows unit tests, native Windows setup/chat/model/delegation/group/session/cancellation/encryption and background remote-control checks, the packaged MCP helper check, universal Mac DMG creation, and Windows NSIS creation**. Actual Mac screenshots are in `docs/screenshots/`; chat responses come from explicit test CLI executables.

The installed Codex CLI’s `app-server` model/list response was also read successfully without requesting inference. Model availability in the app follows the installed CLI/account; no catalog of guessed model names is bundled.

The [iOS simulator workflow](https://github.com/carboy285/opengrokbot/actions/runs/41267663344) passed all **27 tests** for this source. The native controller has no independent local Bot workspace: snapshots come from the host and all mutations go through its authenticated API. Mac and Windows tests use actual local HTTP sockets; the iOS lifecycle test uses an explicit URLProtocol host fixture to simulate network loss and recovery. Physical-iPhone installation and real account/network roaming remain unverified. See [Remote access](REMOTE_ACCESS.md).

## What has not been verified

- A local live Codex inference probe timed out. End-to-end provider inference requires the user’s configured account/model. Claude Code, Grok Build, OpenCode, and Gemini adapters use documented headless protocols and fixtures; live account inference has not been tested for them.
- No Composio project key was supplied. API/MCP tests use controlled HTTP/protocol fixtures; live OAuth, account linking, and tool execution are unverified.
- Mac development packages are ad-hoc signed and not notarized. Windows packages are unsigned. Neither proves a complete downloaded-install/uninstall review on a user’s machine.
- No physical iPhone or user Tailscale account was available. Live Wi-Fi/cellular roaming, real tailnet/Funnel authorization and HTTPS reachability must be checked on the user’s devices. Tests cover the controller protocol, real local host sockets, URLSession decoding, reconnection, revocation and desktop background hosting; they do not establish that a particular firewall, account or network is configured.
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
