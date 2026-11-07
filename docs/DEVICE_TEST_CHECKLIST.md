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
