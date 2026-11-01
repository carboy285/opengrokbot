# Verification

Development runs in Linux; native Mac builds/window tests and iOS simulator tests run in GitHub Actions. Test CLI executables and network fixtures are separate from production behavior. No production chat reply is simulated.

## Supabase account/relay update (0.6.0)

The connected project `kiaenmbtsgoxvfsijzzc` was resumed. Before the migration, its public tables were inspected. `opengrok_account_relay` adds isolated device/packet tables and four account-scoped RPCs. Existing planner tables and the Luma Auth site/callback remain unchanged; only the Grok Bot callback was appended to the Auth redirect allowlist. Email verification remains enabled. Google/GitHub and SMTP credentials were not supplied or enabled.

The deployed database reports RLS on both new tables. All four RPCs deny execution to `anon` and permit `authenticated`; their security-definer implementations use an empty search path and check `auth.uid()`. Device registration cannot replace a public key or change device role. Packet routing checks both devices belong to the signed-in account, enforces host/controller direction, bounds size and queue length, and deletes expired messages.

`supabase/verify-rollback.sql` passed against the actual connected database: account isolation, immutable keys, mailbox delivery, duplicate suppression, cross-account acknowledgment denial and acknowledgment deletion. Test Auth rows/devices/packets were created inside a single transaction and rolled back, without sending email. It does not test an actual Supabase login or a physical phone.

`npm run test:cloud` runs the actual migration in embedded PostgreSQL (PGlite), covering account RLS, table/RPC permissions, anonymous denial, immutable identities, sender direction, packet size, queue bounds, duplicate insertion and expired-ciphertext cleanup. It passed locally; the Windows CI job also runs it.

Apple XCTest covers Curve25519/HKDF/AES-GCM round trips, binding account/peer/request/direction, tampering, expiry inside ciphertext, local approval persistence/revocation, host identity pinning and streamed state patches with deletion/resync. Auth fixtures verify concurrent requests share one refresh and persist the rotated refresh token. iOS lifecycle fixtures use the real client encryption/HTTP stack against an explicit Supabase URLProtocol fixture to sign in, discover a host, send an encrypted command, apply streamed state, recover from a network outage and disconnect without writing a phone workspace. Mac dispatch tests run a real fixture CLI process, preserve exact model selection, and deduplicate sends.

Native Mac UI tests cover the empty single-Bot workspace, real fixture CLI replies, Send/Enter, Shift+Enter, draft preservation, header side panel/model controls, Library/Computer, Escape, Connect Apps, settings, account email/password fields, disabled empty sign-in and the guided local CLI/Composio setup. The universal app and bundled MCP helper are built for arm64/x86_64, ad-hoc signed/verified, and packaged into a verified DMG.

Runtime commit `bcdf5c7a5d596bead5cf38d5451ee519c6f48ba5` passed [desktop CI](https://github.com/carboy285/opengrokbot/actions/runs/41270461498): **34 Mac unit tests, 2 window tests, database tests, existing Windows checks and universal Mac packaging**. The [iOS simulator run](https://github.com/carboy285/opengrokbot/actions/runs/41270461442) passed **27 tests**. Download links and the Mac SHA-256 are in [Downloads](DOWNLOADS.md). Later commits update documentation/screenshots only.

## Existing local CLI/Windows coverage

The Windows 0.5.0 implementation remains on its earlier pairing protocol; it is not compatible with the new iOS account controller. Its 18 unit tests cover workspace validation/migration, structured CLI events/session arguments, Composio fixed-origin requests/allowlists, MCP JSON/SSE contracts, secret redaction, provider configurations, Bot/model inheritance, private/shared memory, provenance, group delivery, bounded delegation and legacy HTTP/Tailscale ownership.

Native Electron smoke checks launch the actual app, complete setup, send Unicode through a real fixture CLI process, resume sessions, stop replies, load model catalogs, create/delegate/group Bots, validate IPC, persist/reopen data, exercise encrypted storage, and keep the legacy remote host running in the system tray. Packaging verifies the NSIS installer and unpacked MCP helper. Browser UI checks use an explicit IPC fixture.

Other Apple tests cover model persistence/migrations, save failures, Keychain, five CLI event formats, prompts/session/model arguments, actual subprocess output/discovery/cancellation, Composio API contracts, private MCP configuration and teamwork bounds. Python checks parse Swift, validate Xcode references/resources/plists and run four synthetic ASAR extraction tests. Static parsing alone is not native compilation.

## Practical limits

- No live signup email or provider OAuth sign-in was sent during implementation. Supabase's default SMTP delivers only to project-team addresses; configure custom SMTP for public signup. Google/GitHub browser flows are included but deferred until their providers are configured. Physical iPhone installation, Wi-Fi/cellular roaming and a real hour-long account session must be checked on user devices. Fixture token rotation tests do not substitute for those checks.
- No Composio project key was supplied. API/MCP tests use fixtures; live OAuth and tool execution remain unverified. An earlier live Codex inference probe timed out. All five CLI adapters use actual subprocess APIs and documented formats, but provider/model access requires the user's CLI accounts.
- Mac packages are ad-hoc signed, not notarized. Windows packages are unsigned. iPhone installation requires your Xcode signing team. Simulator checks do not prove physical-device installation.
- The relay polls rather than streaming a desktop screen. The Mac must stay awake and online. Supabase free-project inactivity, storage/egress/rate limits and mail quotas apply. Packets have bounded size/expiry; the app does not retain a cloud chat backup or provide an always-on cloud computer.
- Native screenshots show actual app windows. Pixel-perfect equality with the supplied proprietary app screenshots has not been established. Voice, file attachment upload, wake management and scheduled routines remain unavailable.

## Reproduce

```bash
python3 -m pip install -r scripts/check-requirements.txt
python3 scripts/check_project.py
python3 -m unittest discover -s scripts -p 'test_*.py' -v
npm ci
npm run test:cloud
npm run test:desktop
CHROMIUM_PATH=/path/to/chromium npm run test:ui
```

On Mac, select **GrokBotMac** in Xcode, test, then run `./scripts/build-macos.sh`. Select **GrokBot** and an installed iPhone simulator for iOS tests. On Windows run `node scripts/test-electron.cjs`, `npm run dist:windows` and `node scripts/test-packaged-helper.cjs`.
