# Proposed browser workflow recording

Workflow recording is not currently implemented. The local browser can read pages for a bot, but it does not record reliable, replayable user interactions. The app must not present a recording button until those operations are supported.

An implementation should use the existing per-bot browser profile and a versioned, local workflow file owned by that bot. Recording should capture navigation and explicit user-selected interactions as structured steps, with stable selectors where available; it should exclude passwords, cookies, authorization tokens, payment details, and private form values. Before saving, show an editable preview so the user can remove steps and replace sensitive values with runtime inputs. Sharing a workflow should export only the reviewed steps and declared inputs, never the browser profile or credentials.

Replay should stop when a target is missing, ambiguous, or the page has changed, and show the user which step needs attention. A saved workflow is not approval for a consequential action: sending, publishing, purchasing, booking, deleting, and changing calendar data require an explicit review of the actual pending action. The user should be able to cancel or take over, and the run history should record step status without storing sensitive page contents.

Before enabling this feature, verify on supported Mac and Windows versions that recordings and replays survive navigation, handle changed pages and failures, preserve profile ownership, do not capture secrets, and stop before consequential actions. Remote viewing and replay must follow the same host-device authorization and offline behavior as the existing browser. Do not treat simulated UI tests as proof that real browser interaction is reliable.
