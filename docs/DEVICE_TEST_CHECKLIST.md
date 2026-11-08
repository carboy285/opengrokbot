# Device test checklist

Automated checks (unit tests, fixture UI tests and builds) cannot prove that voice, microphone, Apple apps, Messages, 1Password or real websites work. Run this short list on your own Mac and iPhone before relying on a release. Note anything that fails and send it back; each item names what to look for.

## Mac (about 15 minutes)
1. **Launch.** Right-click → Open the first time. The app opens without a crash and shows your Bots.
2. **Subscription sign-in.** Setup → *Sign in in Terminal* opens Terminal with the provider login. After signing in, send a message; the Bot answers. The Bot header menu shows *Using your … sign-in*.
3. **API key.** Settings → API Keys: save a key; the header menu changes to *Using API key ••••1234*. Remove it; it goes back to sign-in.
4. **Model menu / compare.** Switch providers from the header menu. Turn on *Compare all enabled models* with two providers; both answer, neither runs tools.
5. **Page reading.** Ask a Bot to read a page. The chat shows one line (title · site), not the page text. The Bot describes what is actually on the page (it opens the screenshot).
6. **Browser actions.** Ask a Bot to search the web, open a result, scroll, and click a harmless link. Ask it to click something like *Buy* or *Submit*: a dialog must appear. Decline: it must stop.
7. **Secure login.** Settings → Secure Logins: save a login for a real site. Ask a Bot to sign in: the dialog shows the site and account, Touch ID/password is required, the page fills and submits, and the password never appears in the chat. Try a look-alike site: it must refuse.
8. **1Password (optional).** With `op` installed, add a 1Password item login. Signing in prompts 1Password and works.
9. **Apple Connections.** Turn on Calendar, Reminders, Contacts: macOS asks permission. Mail and Notes ask on first use. Messages needs Full Disk Access. Each read works; adding a reminder or event shows an approval dialog.
10. **Triggers.** Ask a Bot to run a task *when an email arrives* (Mail on) and *when an event starts*. Send yourself a test email / create an event a few minutes ahead; the routine runs.
11. **Always on.** Settings → Computer → *Keep this Mac awake…*. Start a long task and let the display sleep: it keeps going.
12. **Knowledge.** Header menu → Add knowledge files… (a PDF and a text file). Ask a question only the files can answer; the Bot searches and answers.
13. **Usage.** Settings → Usage & Billing shows today's messages and estimated tokens, split by provider and Bot, and marks API-key messages.
14. **Voice.** Open voice mode: the compact card with orb, waveform, settings, captions, mute and end buttons appears over the chat. Speak, hear the reply start quickly, talk over it, mute, end. Try Groq and (if you run one) NVIDIA NIM speaking.

## iPhone (about 5 minutes)
1. Connect to your Mac. Chats load; page-read lines are short summaries.
2. Voice mode shows the same compact card and works with headphones and without.
3. Send a message; the Mac answers.

## Windows (about 10 minutes)
1. Install, sign in through a CLI, send a message.
2. Settings → API Keys: save/remove a key; the Bot uses it.
3. Page reads show a summary line; slow pages return partial text instead of an error.
4. Voice card, mute, captions, Groq / NVIDIA NIM speaking.

## Apple writes (Mac)
- Reminders: ask a Bot to add, rename, finish and delete a reminder. Add/rename/finish should not prompt (default); delete should prompt.
- Calendar: change and delete an event by title; try two same-named events and confirm it asks for the `on` date.
- Notes: create a note, append to it, delete it (goes to Recently Deleted).
- Contacts: add a contact, then add a phone number to it.
- Mail: send an email to yourself (prompt appears), draft one, reply to a message, mark read/flag, trash.
- Messages: send a text to yourself by name and by number (prompt appears; macOS asks for Automation access to Messages the first time).

## Next-version features (Mac / iPhone / Windows)
- Phone notifications: Settings → Computer → Phone notifications. Subscribe to the topic in the ntfy app, press Send a test, then background the app and let a Bot finish a reply.
- Phone approvals: ask a Bot to send an email to yourself. The Mac sheet and the iPhone alert should both appear; answer on the phone and confirm the Mac sheet closes. Sign-ins (Touch ID) must stay Mac-only.
- Ask a Bot shortcut: run "Ask OpenGrokBot" from Siri/Shortcuts on iPhone and Mac with and without a Bot name.
- Menu-bar Ask a Bot window: send a request, confirm the Bot replies in the main window.
- Mail search: `days`, `scope: all`, unread only, attachment names.
- Memory: say "remember I prefer window seats", then "forget the window seats"; check Settings → Shared memory and Bot details.
- Templates and sharing: create a Bot from a template chip; Share this Bot… then Import a shared Bot… on another Mac.
- Knowledge: add a PDF and a screenshot, ask the Bot to read both (read_knowledge). Windows: PDF only (no photo text recognition).
- Windows: add a 1Password login (needs the `op` CLI).

## 0.8.3: other computers and Bot copying
- Mac: sidebar top-left switcher → choose the Windows PC. The window should show its Bots (pinned and recent) with the usual chat, send a message, stop, retry, change the model from the header menu, create a Bot, pin and delete.
- Switch back to "This computer" and confirm this Mac's own Bots and chats are untouched.
- Right-click a Bot → Copy to another computer: Mac → Windows, Windows (viewing) → Mac via "This computer", and viewing Windows → another computer. Check the copy has the history, memory, Knowledge files, paused routines and a note saying where it came from, and that the Bot answers on the new computer (it starts a fresh AI session).
- Windows host with the clock set a few minutes wrong: Settings → Computer should say the clock is off (rather than the viewer timing out).

## 0.8.4: Computers screen and copy everything
- Mac: the "This computer" button (top of the sidebar) opens the Computers screen. Right-click a Bot → "Copy to another computer…" opens the same screen with that Bot picked. Confirm nothing flickers.
- Look at another computer from the screen and switch back.
- Copy just one Bot; copy everything with only Bots ticked.
- Turn on "Share keys and connectors" on both computers (Mac: Computers screen; Windows: Settings → Computer). Copy everything with keys and connectors ticked in both directions. Check the AI provider keys appear (Settings → API keys), voice keys work, and Connect Apps shows the same project and apps.
- With sharing off on either side, the copy should say to turn it on, and send nothing.

## 0.8.5: remote settings and audit fixes
- View the Windows PC, press "You": it should say "Settings for <PC>" with its version, AI CLIs, API key status, voice keys and connectors. With "Share keys and connectors" on at the PC, save and remove a test key there and confirm the status changes; with it off the buttons are disabled.
- "Connect apps" and the status line at the bottom of the sidebar open the same screen while viewing the PC; "Open this Mac's settings" reaches this Mac's own.
- Header model menu on the PC lists every installed provider with models; picking one changes the Bot on the PC; a new Bot shows the PC's default provider before its first reply.
- Delete a Bot on the PC: the row disappears at once. Switching shows "Connecting to…". Search clears when you switch. "Copy everything" opens with only Bots ticked.

## 0.8.6: visual pass (Mac, Windows, small iPhone change)
- Chat column is about 55% of the window at 1100 pt wide, text 16 pt, nothing clipped.
- Sidebar top: only the two round buttons. Hero card shows the primary Bot only; other pinned Bots sit at the top of the list with a pin. Footer: profile circle, Connect apps, and a blue arrow only when an update is available (staged → "Restart to update").
- Viewing another computer: a "Viewing <name> · Back to this Mac" bar appears under the buttons and returns to the Mac; Settings → Computer opens the Computers screen.
- Message box: 46 pt pill, plain +, round send/voice/stop button; + menu has Attach files, Paste image, Export conversation.
- Settings → Accent = Neutral turns the send/voice/stop circles neutral; the copy icon next to the account email copies it.
- Windows: same sidebar/footer/composer; no folder picker or "This computer" button in the header; Settings → Computer still has "View another computer".

## 0.8.6 (continued): palette, message actions, dictation, permissions, voice, Teach a task
- Ctrl/⌘K and Ctrl/⌘F open the palette on Mac and Windows; typing filters Bots (shows the last message); up/down/return choose; Escape closes it. New group chat and Computers appear on Mac only (hidden while viewing another computer).
- Bot row menu: Pin, Move to new section, Mark as unread (dot clears on opening), Rename, Copy conversation ID, Hide from sidebar (still found in the palette), Delete (asks first).
- Hover a message (Mac, Windows): React shows six emoji, Reply quotes it in the box, More has Copy text, Copy as Markdown, Retry (last Bot message), Delete. iPhone: long-press shows the same; reaction and delete go through the computer, so update the computer first.
- Create a Bot (Mac, Windows, iPhone): Create stays disabled until a name is typed; 14 shapes, 10 colours, optional description. From iPhone, check the shape and colour arrive on the computer.
- Mic in the message box: Mac and iPhone ask for Microphone and Speech Recognition on first use and write words into the box while you talk; denying shows a one-line note. Windows: needs a Groq/OpenAI/ElevenLabs key under Settings → Voice; tap to start, tap to stop, the text appears after a moment.
- Settings → Permissions (Mac): Use my rules; add an Always ask rule for Calendar, then ask a Bot to add an event and confirm the dialog appears even if the app toggle says not to ask; add an Allow rule for Notes and confirm no dialog; confirm deleting, sending and saved logins still ask. Windows: add an Always ask rule for a site and confirm a harmless click there asks.
- Bot details: the Voice chat card (voice, speed, language) is per Bot (compare two Bots). Routines list Pause/Resume/Delete. Providers & models is collapsed on Mac unless the Bot has no provider.
- Teach a task (Mac): + menu → Teach a task; switch to another app and click around; come back, add a typed step and a "secret" step; Stop; name and save; check the Bot’s memory shows numbered steps with the secret hidden.
- Connect apps (Mac, Windows): avatar stack when something is connected, chips filter, View all on a category jumps to it.
- Voice speed (compare with 0.8.5): time to first word, gap between sentences, how soon it answers after you stop talking. Try Apple, Groq, OpenAI, ElevenLabs. Speed 0.75× and 1.5× should sound clean.

## 0.8.7: smoothness, hidden browser, Composio search, VM on another computer
- Smoothness (Mac): open a long chat; send a message and watch it stream: the text should appear steadily with no stutter and the sidebar should not flicker. Click between Bots quickly: no pause. Quit and reopen right after a change (rename a Bot, react to a message): the change must still be there.
- Smoothness (Windows): same checks; also leave a long reply streaming while typing in the message box.
- Pinned Bots: every pinned Bot is a tile at the top (Mac, iPhone, Windows), the main Bot first; unpinned Bots are rows below. Pin and unpin from the row menu.
- Hidden browser (Mac): ask a Bot to read a page. No window opens. A bar above the message box says what it is doing; Show browser brings the window up, Hide browser puts it away; Pause & take over shows it and pauses the Bot, Resume hides it again. Bot details → Open local browser opens it directly. Closing the window while the Bot is working only hides it. Check that the page screenshot the Bot receives is not blank.
- Hidden browser (Windows): same; Show browser / Hide browser in the bar. If the screenshot comes back empty, say so: that is the hidden-window capture risk.
- Composio search: with a Composio project connected, ask a Bot to search the web. The result says “via Composio” and no browser opens. With Composio removed, the search uses the hidden browser and no “via Composio” label. If Composio refuses the search tool, the result says “Composio search failed … Used the browser instead.” Report the exact message: the tool names (COMPOSIO_SEARCH_DUCK_DUCK_GO_SEARCH, COMPOSIO_SEARCH_WEB) were taken from public notes and are unverified.
- VM on another computer: on the computer with a VM, Bot details → Linux VM → turn on Allow guest commands, then “Let my other computers use this VM”. On another computer, Bot details → VM on another computer → Choose a computer → Use the VM. The first time, approve the new device on the sharing computer. Ask the Bot to run a harmless command (for example /bin/uname -a) and check the output says which computer it ran on. Turn sharing off and confirm the command is refused. Try Mac → Windows and Windows → Mac.

## 0.8.8: connected apps
- Connect Google Drive in Connect apps (Add, Apply, Connect, authorize in the browser, Refresh). Ask a Claude Code Bot “Can you see my Google Drive?” The Bot should search for a Drive tool and answer from it. With “Let Claude Code use connected apps without asking” off, Claude Code may refuse: the chat should then say so (a note about needing permission). Turn the switch on and ask again.
- If the Bot still says Drive is missing, look in the chat for a note starting “Connected apps did not load” (the connection to Composio failed to start) and report its exact words, plus whether Drive shows Connected in Connect apps.
- Other AI CLIs (Codex, Gemini, OpenCode, Grok): ask the same question; they follow their own permission settings, so they may still refuse. Report what they say.
- Prompt check: a Bot with no connected apps should not mention Composio.

## 0.8.9: one shared VM and hand-over
- Settings → Computer → Shared VM (Mac) / “Shared VM for all Bots…” (Windows): set up the VM once. Ask two different Bots to run /bin/uname -a: both run in the same VM.
- On another computer choose that VM under “Shared VM on another computer” (the sharing computer needs guest commands and “Let my other computers use this VM” on). Both Bots there should run commands in it; the old per-Bot VM cards are gone.
- Hand-over: ask a Bot to “open a website in the VM and ask me to log in”. A pop-up “<Bot> needs you in the VM” appears with the reason. Open VM opens the console (on the sharing computer when it is remote). Press “I’m done — continue”: the Bot continues and checks the VM. Try Cancel task too: the Bot should stop and ask what you want.
- Remote VM: the screen preview may stay empty (needs remote VM viewing on the sharing computer, and Screen Recording on a Mac). Clicking inside the VM is only possible on the computer that has it. Report how that feels.
- Two Bots asking at once: the second request waits until the first is answered.

