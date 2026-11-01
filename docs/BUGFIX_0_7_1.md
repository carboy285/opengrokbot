# OpenGrokBot 0.7.1 · build 9

Chats open at the newest message on iPhone, Mac and Windows. Generated text keeps scrolling into view while following the latest message; scrolling up pauses following. iPhone chats support a rightward swipe from the left edge to return home.

Pin preferences now live in the account server, scoped to the account and computer workspace. Changes queue locally during outages and synchronize in either direction. The production `bot_pin_preferences` migration was applied. Update both phone and desktop; older versions keep their local pin behavior. No chats or credentials are added to the pin table.

## Correctness fixes

Reject duplicate workspace/message identities before dictionary construction or SwiftUI navigation. Navigation now uses stable Bot IDs and resets on account/workspace changes. Preserve saved files if loading fails. Prevent stale model requests and auth responses from changing a newer account/provider selection; handle OAuth completion once. Restore desktop drafts without trapping on UUID normalization collisions. Bound avatar image dimensions before decompression. Preserve pending phone sends against older acknowledgments and request a fresh snapshot after inconsistent relay responses.

The original intermittent iPhone crash was not reproduced and its cause is not confirmed. These changes address concrete crash and race paths found by source inspection.

## Scheduling

Ask a Bot to schedule a task at a specific time, or recur hourly, daily or weekly. Specify a timezone for calendar schedules. The desktop interprets bounded `schedule_task`, `list_tasks`, and `cancel_task` action blocks after a successful response and persists tasks with the Bot. Daily/weekly schedules use calendar time in the requested timezone; missed occurrences coalesce into a single catch-up run. A stable occurrence ID prevents duplicate chat delivery after interrupted scheduling. Busy Bots defer tasks; CLI setup must be complete. Closing/quitting the desktop app stops scheduling. Windows may stay in its tray while phone access is enabled.

The supported event trigger is `message_received` from another Bot, with an optional case-insensitive text match. Other external events (email, website changes, files) are not configured. Scheduled and delegated turns cannot create or cancel tasks through the action protocol. Scheduled work does not grant fresh approval for external actions. Tasks can be viewed and cancelled in Bot details on phone and desktop.

## Hosted browsers

Desktop Settings → Computer includes Browserbase configuration. Supply your own API key and project UUID; keys stay in macOS Keychain or Windows encrypted storage. The `browse_web` action opens a fresh isolated cloud Chromium session, reads one HTTPS page and bounded text/links, closes the session, and allows one automatic continuation to summarize its result. No local browser or desktop automation is launched. Sessions are temporary: cookies and login state are not retained, including across requests by the same Bot. Page text is labeled as untrusted context. Forms, purchases, arbitrary browser scripts and authenticated browsing are not implemented. Provider charges/limits apply.

No Browserbase account/key was available during this update, so cloud browsing remains inactive until the owner connects it. API implementation follows the Browserbase session creation and release contracts: https://docs.browserbase.com/reference/api/create-a-session and https://docs.browserbase.com/reference/api/update-a-session.

## Validation limits

Tests, syntax checks, UI automation, protocol checks, database behavioral checks and physical-device validation were not run, at the user's request. Installer compilation/packaging is separate and does not confirm runtime behavior. Mac installers use ad-hoc signatures without notarization and Windows installers are unsigned until publisher credentials are configured.

## Remote desktop workspaces

Mac and Windows include a “This computer” switcher and a remote workspace view. Sign in under Settings → Computer, select your server computer and approve the viewing computer on the server after comparing its controller fingerprint. Chats, Bot creation/deletion, provider selection, and shared pins target the selected server. Mac additionally exposes remote avatar editing and task cancellation. The server must be awake with phone/remote access enabled. Your iPhone can choose the same server.

Remote workspaces use separate in-memory state; viewing a server never replaces the local workspace file or runs its CLI on the viewer. A separate controller encryption identity shares the desktop's existing authenticated account transport and token refresher. Changing accounts invalidates remote views. The server stores no extra long-lived plaintext chat copies for this feature. Browser sessions still run at Browserbase when configured on the server.

Packaging completed: https://github.com/carboy285/opengrokbot/actions/runs/41356220965 compiled iPhone sources and the universal Mac app, packaged Mac/Windows installers, and published 0.7.1 from runtime commit `b6edab6109d78b41b1f61c9207d89533e9bbd3ab`. No tests were run.
