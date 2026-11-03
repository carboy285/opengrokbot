# Voice mode and image attachments

## Voice mode (iPhone, Mac, Windows)
Tap the waveform button in the message box. Voice mode is hands-free: it listens, sends what you said after a pause, speaks the Bot's reply, then listens again. Talk over a reply to interrupt it (tap the orb as a fallback).

| Platform | Listening (default) | Speaking (default) |
|---|---|---|
| iPhone, Mac | Apple on-device speech recognition, no key | Apple voices, no key |
| Windows | Needs a cloud key (free Groq key works) | Windows voices, no key |

Optional cloud upgrade (Settings → Voice, or the gear in voice mode): Groq (listening), OpenAI (listening + speaking), ElevenLabs (listening + speaking). Keys are stored in the Keychain (Apple) or encrypted with Windows DPAPI via Electron `safeStorage`; they are never committed. Cloud providers receive your audio or the reply text and apply their own quotas.

Permissions: microphone and speech recognition (Apple). Windows asks for the microphone on first use.

Known limits: replies are spoken after they finish generating (not streamed); echo cancellation and talk-over depend on the device and are best with headphones; hardware behavior is untested.

## Image attachments
- Mac: ⌘V pastes a clipboard image or copied file into the message box; the plus popover has Add files and Paste image.
- iPhone: plus menu → Photo library or Paste image. Images are compressed to about 1.5 MB, at most 3 per message, and sent through the encrypted relay. The Mac or Windows host must run this version or newer.

## 0.7.6 additions (updates changed in 0.7.7: see below)
- Replies are spoken sentence by sentence while they stream. Talking over the Bot (or tapping the orb) stops speech and stops the Bot generating.
- iPhone: when the message box is focused and an image is on the clipboard, a "Paste image from clipboard" button appears. The **Talk to my Bot** shortcut (Shortcuts app, Siri, Action Button) opens voice mode with your main Bot.
- Windows: Attach files… in the plus menu, Ctrl+V to paste images, and attachment chips above the message box.

# Notifications, updates and backups (0.7.6)
- **Notifications**: Mac and Windows notify you when a Bot finishes while the app is in the background. The iPhone shows a banner when a Bot finishes in another chat or shortly after you leave the app; it only knows about replies while it is connected (this is not a push service).
- **Updates**: Settings → Updates → *Download update*, then *Restart and install*. Both apps check the download first (size and SHA-256). Mac unpacks the new app next to the current one, verifies its signature, then on restart swaps it in place and reopens it; if the app is in a folder you can't write to, it opens the disk image instead. Windows runs the installer silently, then reopens the app. Restart is blocked while a Bot is replying, and your workspace is kept.
- **Backups**: Settings → Backup (Windows) or Settings → Updates (Mac). Backups are encrypted with your password (PBKDF2-SHA256, 600,000 rounds, AES-256-GCM) and exclude AI sign-ins, API keys and vault secrets. Restore works on the same platform the backup was made on; the current workspace is saved as a safety copy first.
