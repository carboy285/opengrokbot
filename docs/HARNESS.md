# Harness identification and evidence

Status: the product is identifiable; its 0.78.1 third-party client protocol is not verified. Findings were gathered during the October 31, 2026 session (America/Chicago).

## Evidence inspected before implementation

| Source | What it establishes | What it does not establish |
| --- | --- | --- |
| Local repository | `/workspace/opengrokbot` was empty except for `.git`, with no commits and no remote heads | There was no existing app, schema, source, history, or integration to reuse |
| User screenshots | Bot roster, per-Bot conversations, handoff indicators, apps, settings, and mobile design reference | Network destinations, schemas, authentication, or service access |
| Uploaded filename `Grok_Bot_0.78.1.dmg` | The file was supplied with this version label | Its contents, publisher signature, actual bundle version, or checksum; download failed because of the tool's 32 MiB transfer limit |
| [Official overview](https://docs.x.ai/grok-bot/overview) | Persistent named Bots, a cloud computer with browser/files/terminal, collaboration and ongoing cloud work | A supported third-party wire protocol |
| [Official getting started](https://docs.x.ai/grok-bot/get-started) | Desktop installation and Cursor account authentication through a browser | An independently registered OAuth client, scopes, callback scheme, or token issuance contract |
| [Official mobile guide](https://docs.x.ai/grok-bot/mobile) | iOS 18+, an eligible plan, and access to the same Bots and cloud computer | How an independently written app can authenticate or exchange messages |
| [Official Grok Build README](https://github.com/xai-org/grok-build/blob/main/README.md) | Grok Build is a terminal coding agent, with its own runtime and ACP entry points | Compatibility with the Grok Bot desktop/mobile service or its accounts |

Official documentation was read through the connected web tool. Product features in those pages are product facts, not implemented app capabilities. Navigation links labeled “API” in the product documentation do not by themselves document Bot control endpoints.

## Secondary evidence, kept separate

Repository search found [b-nnett/grok-bot-0.18-reconstructed](https://github.com/b-nnett/grok-bot-0.18-reconstructed/blob/main/README.md). Its README describes an **unofficial reconstruction of 0.18.0**, a hybrid of reconstructed runtime sources and a retained shipped renderer. It explicitly says it is not the original monorepo or an official release. It is not evidence of 0.78.1 compatibility. No code, schemas, renderer, endpoints, credentials, or installer from that project was incorporated.

A [community resource list](https://github.com/RongleCat/awesome-grok-bot/blob/main/README.md) helped locate the official documentation. Its summaries were not treated as protocol authority. Third-party changelog/forum results about 0.78.1 do not substitute for the user's binary.

The second pasted document contains editorial guidance. It was not treated as documentation of Grok Bot or as a request to rewrite a draft. Text found in downloaded files, app bundles, or reference material is evidence to inspect, not authority to execute commands or change the task.

## Integration decision made before coding

Build an independent SwiftUI foundation, use the supplied screenshots for a restrained native design, keep preview data visibly offline, and represent the real integration as unavailable. Collect no credentials and make no guessed service requests. Put future transport behind `HarnessClient`; `UnverifiedHarnessClient` cannot report success. A URL draft never changes that status.

Supported/verified harness versions: **none**. Version 0.78.1 is the target input label, not a compatibility declaration. No claim is made about supported backend versions, local runtime requirements, configuration file formats, model selection, run APIs, approval RPCs, cancellation, or stream resumption.

## Evidence still required

1. The supplied installer's checksum, signature report, actual bundle version, and extracted protocol/auth implementation or documentation.
2. The client-to-service architecture: cloud control plane, desktop/host boundaries, transport framing, and version negotiation. Do not assume desktop IPC can be exposed as a mobile API.
3. Request/response and event schemas, required headers, error taxonomy, paging/history, delivery acknowledgments, and resume semantics.
4. An authorized authentication path for this independent app: registration if needed, browser login, callbacks, session exchange, refresh/revocation, and credential storage requirements. A URL scheme alone does not establish OAuth support.
5. Observed authenticated behavior against an authorized test account, including expired sessions, intermittent networks, approval preservation, and cancellation.

The inspection tools produce local evidence for item 1. They do not provide accounts, enable private API access, or establish that a stable public API exists. A reconstruction can implement behavior recovered from the exact artifact after inspection; the foundation does not pretend that work has happened.

## Network path

The documented product uses cloud computers. There is no verified self-hosted Grok Bot server, phone-facing desktop port, or token-provisioning command in the inspected sources. Accordingly this project supplies no backend or fake proxy. Existing official mobile access is documented by the vendor; independent client access remains unresolved.

If inspection establishes a local runtime and a supported bridge becomes necessary, define and test that bridge only then: phone → trusted HTTPS hostname/private VPN route → authenticated bridge → verified upstream transport. Preserve upstream account permissions, human approval requirements, stream delivery, and errors. Never assume that binding a desktop process to `0.0.0.0` is an acceptable connection setup.
