# Remote loading fixes · 0.7.2 (build 10)

The relay's existing access logs showed successful discovery, send, poll and acknowledgment HTTP requests. They do not prove encrypted application responses were decoded or that the workspace appeared on a physical device. The reported PC-to-Mac/phone hang was not reproduced locally; the fixes address concrete failure paths found in the loading code.

- Load a small Bot overview first, then request full conversation history. An overview uses its own revision so it cannot be confused with a full workspace. Authoritative conversations stay on the hosting computer.
- Accept both legacy raw full snapshots and the current snapshot/delta envelope. A mismatched delta requests a full refresh.
- Retry a lost request with the same mailbox ID/payload; command delivery retains its separate stable command ID. State requests stop waiting after 12 seconds of mailbox polling rather than 35 seconds. Individual network calls still have their own network timeouts; this is not a strict wall-clock connection guarantee.
- Preserve errors during retries; never silently change the selected computer after an initial timeout. A bad reply is acknowledged and reported rather than blocking subsequent polls.
- Mac hosts return bounded explicit errors when a valid request format or workspace response cannot be transferred, rather than dropping it and leaving the viewer waiting. Oversized workspaces report a transfer limit.
- Windows provides a Reconnect button, distinguishes approval/retrying/connected stages, and selects the first available Bot when its roster arrives. Sending requires a connected workspace.
- Mac approval wording includes desktop viewers and phones. Approval remains required; encryption and account ownership are unchanged.

## Upgrade and connect

Quit older copies of OpenGrokBot, install **0.7.2** on the host and PC, and reinstall the matching **GrokBot** Xcode target on iPhone with the existing signing team and bundle identifier. Confirm version **0.7.2**, build **10**.

On the hosting Mac/PC, sign into Settings → Computer and enable Allow phone access. On the viewing PC, use This computer to select that host. Compare fingerprints and approve the viewing device on the host. Use Reconnect after updating. On iPhone, sign into the same account and select that same host. The phone controls desktop Bots; it is not a Bot host that a PC can select.

A roster can appear before full history. While the status says loading chat history, the displayed snippet is only a preview. If the full workspace exceeds the encrypted relay limit, the error explains that older conversations must be exported on the host.

No automated tests, syntax checks, UI automation, test database queries or physical-device validation were run, as requested. Existing relay logs were inspected for diagnosis. Installer compilation/packaging is recorded separately and does not establish runtime interoperability.
