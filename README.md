# OpenGrokBot

A free, open-source chat app for **AI CLIs installed on your own computer**, with optional **Composio** tool connections. macOS is the priority: native SwiftUI/AppKit, Liquid Glass on macOS 26, and a universal Apple Silicon/Intel DMG. Windows has an Electron app and Setup EXE. The iOS app signs into the same Supabase account as your Mac or Windows desktop and controls its existing workspace through an encrypted device relay.

Start with **one empty assistant named Grok Bot**. There are no seeded conversations or extra Bots. Ask Grok Bot to create specialists, or add your own Bots when you want separate conversations.

[Downloads](docs/DOWNLOADS.md) · [Setup guide](docs/SETUP.md) · [Verification](docs/VERIFICATION.md) · [Source review](https://github.com/carboy285/opengrokbot/pull/1)

![Native Mac workspace with only Grok Bot](docs/screenshots/macos-workspace.png)

## First launch

1. Choose **Codex**, **Claude Code**, **Grok Build**, **OpenCode**, or **Gemini CLI**.
2. Let the app find your installed CLI, or choose its executable. If it is missing, follow its official installation guide.
3. Sign in through the CLI in your Terminal. The app checks Codex login status; other providers validate their configured account on the first message.
4. Optionally enter your **Composio project API key**, choose tools, and authorize each account in your browser. Return and refresh connections.
5. Start chatting. Each Bot keeps a separate CLI session. You can stop a response, retry a failed response, switch providers, and export conversation text.

The app is free. AI providers, local model configurations, and Composio have their own pricing, quotas, and requirements. Free inference is not guaranteed.

## Platforms

| Platform | Implementation | Distribution |
| --- | --- | --- |
| macOS 14+ | Native SwiftUI/AppKit; Liquid Glass on macOS 26, material fallback earlier | Universal `.app` in a drag-to-Applications `.dmg` |
| Windows x64 | Electron with an isolated, sandboxed renderer | NSIS Setup `.exe` |
| iOS 18+ | Native SwiftUI remote controller for the desktop’s Bots/chats/models | Xcode project; shared sign-in and locally approved Mac access |

The development Mac build is ad-hoc signed and not notarized. The Windows build is unsigned. iPhone device installation requires your own signing team. See the [Mac](docs/MACOS.md), [Windows](docs/WINDOWS.md), and [iPhone](docs/DEVICE_SETUP.md) guides.

## iPhone remote control

In Mac **Settings → Computer → iPhone remote control**, create an email account, confirm the email, sign in and enable **Allow phone access**. Sign into the same account on your iPhone. Compare its device fingerprint and select **Approve phone** on the Mac, then choose your Mac on the phone. No VPN, pairing URL or router setup is required.

The phone controls the same Bots, chats, memories, active models and running tasks without saving an independent workspace. Supabase handles accounts, device discovery and encrypted temporary packets; the Mac runs all AI CLIs. Revoke individual phones on the Mac. Google/GitHub buttons appear after their providers are configured in Supabase. Default Supabase email delivery is restricted to project-team addresses; custom SMTP is needed for general signup. See the [connection guide](docs/REMOTE_ACCESS.md).

![Native Mac account setup](docs/screenshots/macos-account-setup.png)

**0.9.7** adds actions on heads-ups and a Today card, image and video generation, tools for local models, and [web access](#web-access) from any browser. **0.9.6** adds heads-ups: Grok Bot reaches out first about important email, upcoming meetings, double-bookings and your day ([details](#heads-ups)). **0.9.5** adds ChatGPT-style follow-up suggestions, starter ideas, edit & resend and regenerate; rich replies (tables, lists, highlighted code, images); sentence-by-sentence voice and streaming Codex answers; an Ollama model manager; search across chats with pins; Markdown/PDF export; Copy diagnostics; and a voice hotkey from anywhere. **0.9.4** makes the open-source voice start on the Mac (a WebKit fix), switches to quicker default models that use several cores, adds Test speed and a graphics-chip check in Settings → Voice, and tidies the chat header and composer controls. **0.9.3** rebuilds voice mode: free open-source voice that runs on your computer (Whisper listening, Kokoro speaking, with a model recommended for your machine), turn-taking that waits when you trail off plus hold-to-talk, a short “one sec” and spoken tool steps while a Bot works, short spoken replies from quicker models (Haiku, Gemini Flash, Codex low effort), card / full-screen / mini layouts that stay on when you switch Bots, and Ollama and LM Studio as self-hosted chat models. See docs/VOICE.md. **0.9.2** is a UI-only update that brings the Mac, iPhone and Windows apps much closer to Grok Bot: a deeper dark look, avatars that show when a Bot is working or waiting for you, approval cards in the chat (Deny / Allow once) instead of system pop-ups, question cards with answer buttons, Bot-to-Bot messages shown with the sender’s avatar and name, foldable tool-step pills, typing dots and a quieter composer. **0.9.1** makes the shared Linux VM work first time: it installs and repairs its own guest tools, waits and retries the first command test, signs in without a password prompt, and adds copy-and-paste, Update guest password and Delete VM. **0.9.0** makes the shared Linux VM set itself up (Windows: one Set up button), fixes the Mac not listing the PC's VM, starts a stopped VM before Bot commands and tells Bots whether the VM is ready. **0.8.9** gives all Bots one shared Linux VM (here or on another of your computers) and a pop-up that hands the VM to you when a Bot needs you in it, then lets the Bot carry on. 0.8.8 fixes connected apps (Bots now know about, and can reach, the Composio apps you connected, and the chat says why when they can’t) and includes everything from 0.8.7, which was never released. Claude Code needs a new switch in Connect apps to use connected apps at all. **0.8.7** (never released, now part of 0.8.8) is a smoothness and plumbing update: less lag (background saves, throttled streaming, rows that redraw only when they change), pinned Bots back as tiles at the top, a Bot’s browser that stays out of sight until you press Show browser, web search through Composio’s search tool instead of the browser, and a Bot can use a Linux VM that runs on another of your computers (Mac or Windows, either way).

**0.8.6** adds a ⌘K command palette, Bot row menus, message hover actions (reply, react, copy, retry, delete), a small Create a Bot dialog, a mic for dictation, Teach a task (Mac), a Permissions page with rules, per-Bot voice settings, a refreshed Connect apps screen, and much faster voice (earlier first words, shorter waits, parallel speech fetching, a speed slider). It also includes a visual pass: a narrower chat column with 16 pt text, a quieter sidebar (one hero Bot, a cleaner footer, an update arrow), a taller pill message box and a working Accent setting. Other computers are reached from Settings → Computer or the View menu.

**0.8.5** makes the remote view closer to the real thing: “You” and “Connect apps” show the viewed computer’s own settings (CLIs, API keys you can set, connectors), the model menu lists that computer’s providers and models, and the issues found in the 0.8.4 audit are fixed. Bot details, attachments, usage and updates for the other computer are not remote yet.

**0.8.4** replaces the flickering Copy menu with a Computers screen and adds one button to copy everything (Bots, AI and voice API keys, connectors) from the computer on screen to another; keys and connectors need “Share keys and connectors” switched on at both ends. Real-device behavior is unverified.

**0.8.3** lets the Mac show any other computer on your account exactly like its own app (switcher at the top of the sidebar), and copy a Bot with its provider, memory, history, paused routines and small Knowledge files between computers (Mac and Windows both). A Windows PC whose clock is wrong now reports it. Real-device behavior is unverified.

**0.8.2** lets Bots read, write, change and delete in Calendar, Reminders (lists and #tags), Contacts and Notes, and send, reply to and manage Mail and Messages on Mac; adds phone approvals and ntfy notifications, Ask a Bot from Siri/Shortcuts and the menu bar, wider mail search, forgetting memory, Bot templates and sharing, reading whole Knowledge files and photos, and Windows PDF knowledge and 1Password logins. Real-device behavior is unverified; see [the checklist](docs/DEVICE_TEST_CHECKLIST.md).

**0.8.1** gives voice mode a themed card that can be dragged on desktop and floats under the agent's name on iPhone, and adds Google AI Studio (Gemini) and NVIDIA Cloud speech. NVIDIA Cloud uses NVIDIA's gRPC speech service and has not been tested against it.

**0.8.0** is the big update: Bots can search the web and click, type and scroll in their own browser (consequential actions ask for approval), sign in through secure logins or 1Password without seeing passwords, search a per-Bot Knowledge folder, and start routines from new email or an upcoming calendar event; the Mac can stay awake while Bots work; there are Terminal sign-in buttons, a chat-header model menu with compare, a real Usage screen, and Windows API keys. See [the device checklist](docs/DEVICE_TEST_CHECKLIST.md).

**0.7.9.1** shows a short page summary in chat instead of the raw text, lets Bots work through up to 40 steps and retry another way after a failure, returns partial pages instead of timing out, adds Groq and NVIDIA NIM (self-hosted Magpie) speech, speeds up voice replies, and gives voice mode a new compact card on iPhone, Mac and Windows. Note: the NIM option needs your own NIM server; NVIDIA's hosted API uses gRPC and isn't supported.

**0.7.9** (Mac) redesigns **Connect Apps** with search, categories and many more apps; adds **Apple Connections** so Bots can look at Calendar, Reminders, Contacts, Mail, Notes and Messages once you turn each on (adding events or reminders needs your approval); and adds **Secure Logins**, where a Bot can sign in to a saved site after you approve with Touch ID or your Mac password, without ever seeing the password.

**0.7.8** lets Bots see a screenshot of the web pages they browse and adds optional per-provider API keys on Mac (Settings → API Keys).

**0.7.3** hides the horizontal scrollbar under pinned Bots on Mac while preserving sideways scrolling. [Downloads](docs/DOWNLOADS.md).

The **0.7.2 update** improves remote bot loading between Windows, Mac and iPhone with a smaller initial roster, compatible workspace replies, reconnect controls and visible errors. It also adds recent-use sorting for unpinned Bots, visible local Bot browsers and Linux VM setup through UTM/VirtualBox. See [0.7.2 remote setup and limits](docs/REMOTE_0_7_2.md). It retains [0.7.1 features](docs/BUGFIX_0_7_1.md), including shared pins and scheduled tasks. Local browser profiles replace the cloud-browser requirement.

## Bots, models and teamwork

Click the Bot’s name at the top of a conversation to open its side panel. **Details** contains provider and model controls; **Library** lists real files in its working folder; **Computer** shows its local runtime. Enable providers you want available, then choose **one active provider** and its model. Only that selected model answers for that Bot. Codex and OpenCode can load their local model catalogs; exact model IDs can also be entered. A blank model uses the CLI’s default.

![Native Mac Bot side panel](docs/screenshots/macos-bot-details.png)

Press **Enter** to send; **Shift+Enter** adds a line break. Your unsent draft stays in place when the side panel opens.

Try: “Make me a bot called Travel that plans trips, keeps answers short, and never books without asking.” The assistant can create the Bot with its job description and selected model, save private or shared memories, and send another Bot a request with just the relevant context. The specialist answers asynchronously in its own chat and returns a labeled reply to the requesting chat. Ask for a group with 2–8 existing Bots to work in a shared conversation; each member uses its own selected model. No extra Bots exist at first launch.

Operations apply only after successful CLI completion. The app records messages as coming from Bots, never as human messages or approvals. Internal operations do not include external sending, purchases, approval, or Bot deletion. Only the user-facing sidebar Delete action deletes Bots. CLI and Composio permissions still govern external tools. Model cooperation is required; fixture tests establish routing and persistence, not how reliably a live model follows the protocol. Teamwork is limited to 8 operations per turn, 12 deliveries per chain and 4 hops.

## Chat and tools

The desktop apps launch actual local CLI subprocesses. Prompts use stdin; Grok Build uses a private temporary prompt file because its documented headless mode requires that. Structured events update replies, and provider session IDs resume subsequent messages. Adapters cover each provider’s documented headless format; account/model availability is determined by that installed CLI.

Composio setup uses the documented v3.1 Tool Router API with a stable, randomly generated user ID for this installation and an explicit toolkit allowlist. Authorization links and connection states come from Composio. Selected tools reach the CLI through an app-bundled stdio MCP proxy. The **project API key is never passed to the CLI or model**; the proxy uses the scoped MCP session URL returned by Composio. Connection management is handled in the app rather than automatically by the model.

The app does not add approval-bypass flags. Codex runs with a read-only local workspace; other providers retain their configured permissions. Remote MCP tool actions can change connected accounts’ data according to the CLI’s tool permissions and your Composio authorization. Review those settings before asking the assistant to act.

This independent app does not sign in to the proprietary Grok Bot service, sync its cloud Bots, or control its cloud computer. Historical binary investigation is documented separately in [HARNESS.md](docs/HARNESS.md). It is not needed for local CLI chat.

## Heads-ups

Grok Bot can reach out first instead of waiting for you to ask. Turn it on in **Settings → Heads-ups** after connecting Gmail and/or Google Calendar in **Connect apps**. The app then checks every few minutes in the background and posts into Grok Bot's chat, with a Windows notification:

- **Important new email.** New unread mail (promotions, social and forum tabs are skipped) goes to your selected AI CLI, which decides what actually needs you. If nothing does, you get one quiet "nothing needs you" line and no notification.
- **Upcoming meetings.** A reminder 5–30 minutes before each event, with the join link.
- **Double-bookings.** A note when two events overlap.
- **Morning brief.** Once a day at the time you pick: today's schedule and the email waiting on you.

The first check only records what is already in your inbox, so turning heads-ups on doesn't flood the chat. Quiet hours keep heads-ups in the chat but silence notifications. While heads-ups are on, closing the window keeps the app running in the tray; **Open at sign-in** starts it there when you sign in.

Heads-up turns are read-only. They run without Composio tools, and any app operation they ask for is ignored. Email text is passed to the model marked as untrusted data. To act on a heads-up, reply to Grok Bot normally. That reply runs with your usual tools and permissions, in the same CLI session that saw the email. Heads-ups use Composio's tool execution API with your project key; that endpoint and Composio's Gmail/Calendar response shapes are covered by fixtures, not yet by a live account.

**On the Mac,** heads-ups use Mail and Calendar on the Mac itself; switch them on under **Connect apps → This Mac**, then turn on **Settings → Heads-ups**. You get meeting reminders, double-bookings, a morning brief and new mail from people (newsletters and automated senders stay quiet), as a card in Grok Bot's chat, a Mac notification when the app is in the background, and a phone alert if phone notifications are on. Mac heads-ups don't use an AI model yet; they never reply, send or change anything.

## Image and video

Add a key under **Settings → API Keys → Image & video** for Flux (Black Forest Labs), Google (Imagen and Veo), OpenAI images or Replicate (which reaches many more image and video models). Then ask any Bot for a picture or a video. The app calls the provider with your key, which the AI never sees, saves the file in that Bot's folder and shows it in the chat. Videos can take a few minutes. Each provider bills its own account. Pictures and videos are only made on turns you start, never by routines or heads-ups.

## Local models with tools

Ollama and LM Studio models get the same app tools as the CLIs through native tool calling: web search, page reading, schedules, image generation, and on the Mac Reminders, Calendar, Mail, Notes, Contacts and Messages. With Composio connected, they can look up and run your connected apps' tools. Anything that sends, creates, changes or deletes asks you first, and scheduled routines can only read. Smaller models follow tools less reliably; Qwen 3 and Llama 3.1 8B handle them best of the suggested models.

## Web access

On Windows, **Settings → Web access** lets you use OpenGrokBot from a browser on your phone, tablet or another computer. Choose a username and a password of at least 10 characters, then pick **Wi-Fi** (devices on your home network, at `http://<this PC>:8765`) or **Tailscale** (your devices anywhere on your tailnet, over HTTPS at `https://<this PC>.<tailnet>.ts.net:8443`; needs Tailscale on both devices). Bots still run on the PC, so it has to stay on with OpenGrokBot open; closing the window keeps it in the tray.

Over the web you can chat, use Bots, heads-ups and approvals. The vault, API keys, saved logins, app connections, VMs and the web access settings stay on the PC. The password is stored only as a hash; five wrong tries lock that device out for a while; **Sign out all devices** ends every session. Web access for the Mac app is not built yet; the iPhone app already controls a Mac.

## Data and credentials

**Optional provider API keys (macOS).** Subscriptions (ChatGPT, Claude, Grok) work by signing in through the provider's CLI; no key is needed. To use pay-per-token API access instead, open **Settings → API Keys** and save a key for Codex/OpenAI (`CODEX_API_KEY` and `OPENAI_API_KEY`), Claude Code (`ANTHROPIC_API_KEY`), Grok Build (`XAI_API_KEY`) or Gemini CLI (`GEMINI_API_KEY`). A saved key replaces that CLI's sign-in until removed, so usage is billed to the API account. Keys are kept in the Mac Keychain and passed to that CLI only through its process environment, never in arguments, files, or prompts. OpenCode keeps its own keys (`opencode auth login`). The Windows app does not have this setting yet.

Conversation text and session IDs are stored locally in normal application data directories. AI CLIs send prompts to their configured provider or local model. CLI login credentials remain with those CLIs.

Composio project credentials and scoped session URLs stay in **macOS Keychain** or **Windows encrypted device storage**. They are not placed in command arguments, generated MCP configuration files, or logs. MCP configuration uses environment placeholders in private per-Bot working directories. Composio API requests go to its fixed HTTPS origin; returned browser/MCP URLs must use trusted Composio HTTPS hosts. Removing the project locally stops access from new runs; revoke connected accounts in Composio to remove authorization at the service.

The separate device vault stores secure notes in Keychain/Windows data protection. It is not exposed to Bots. Older preview workspaces migrate away from known fixtures while preserving authored notes and custom Bots; the original workspace is backed up before migration.

The Mac app runs outside App Sandbox so it can execute CLIs installed on the host. The Windows renderer has no Node access; the main process validates IPC and owns subprocesses, credentials, and tool connections.

## Build

On a Mac with Xcode 26+:

```bash
./scripts/build-macos.sh
```

Or open `GrokBot.xcodeproj`, select **GrokBotMac > My Mac**, and run. The MCP helper is built and embedded automatically. Select **GrokBot** for the iOS source target.

On Windows with Node.js:

```powershell
npm ci
npm run start:windows
npm run dist:windows
```

Apple targets have no third-party runtime dependencies. Windows dependencies are pinned in `package-lock.json`. The supplied screenshots inform the dark layout, avatars, centered chat header, glass composer, and settings. Native Apple glass is used on supported OS/SDK versions; Windows uses its own translucent styling. Pixel-perfect equality with the references has not been established.

## Verification and limits

```bash
python3 -m pip install -r scripts/check-requirements.txt
python3 scripts/check_project.py
python3 -m unittest discover -s scripts -p 'test_*.py' -v
npm ci
npm run test:desktop
npm run test:cloud
CHROMIUM_PATH=/path/to/chromium npm run test:ui
```

Native CI compiles Apple targets, runs XCTest, builds the universal DMG, captures actual Mac windows, and builds/tests the Windows app and installer. Tests include real fixture subprocesses, saved-session resumption, Unicode replies, Composio request contracts, MCP JSON/SSE transport, secret redaction, persistence, and encryption. Test fixtures are separate from production replies.

Live model inference and Composio OAuth/tool execution require configured user accounts. A Composio project key was not supplied during implementation, so live authorization and tool execution are unverified. Voice, file attachments, a built-in cloud computer, remote screen sharing, and power/wake management are not implemented. Physical-phone roaming, live email delivery and OAuth provider sign-in have not been exercised with user accounts. See [verification details](docs/VERIFICATION.md).

## License

Original code and geometric artwork are [MIT licensed](LICENSE). This project is not affiliated with xAI, Anthropic, OpenAI, Google, Cursor, or Composio. Proprietary binaries and assets are not redistributed.
