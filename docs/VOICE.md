# Voice mode and image attachments

## 0.9.3: a voice that sounds and behaves like a person
- **Open-source voice on your computer (Mac and Windows):** Whisper listens and Kokoro-82M speaks, with no key and nothing sent anywhere. Settings → Voice recommends models for your machine (memory, cores, Apple silicon or a graphics chip) and downloads them once (about 160–600 MB). You can choose smaller or larger Whisper models, three Kokoro sizes and ten Kokoro voices, preview a voice, or remove the models. The iPhone keeps Apple's on-device voice.
- **Turn-taking:** voice mode waits longer when you trail off (“and…”, “um”, a comma) and less after a question. Choose Quick, Normal or Relaxed. Press and hold the orb (or Space on a computer) to keep talking as long as you like; it sends when you let go.
- **No dead air:** while the Bot starts its answer you hear a short “one sec”, and what it is doing (“Reading a page.”, “Asking Calendar Agent.”). Both can be turned off.
- **Faster, human replies:** in voice mode Bots are told they are being heard, so they answer in one to three short spoken sentences, and use a quicker model: Claude Code uses Haiku, Gemini CLI uses Gemini Flash, Codex thinks less (low reasoning effort). Each provider's voice model can be changed (Windows: Settings → Voice; Mac: defaults key voiceModels). The phone tells the computer when its voice mode is on.
- **Better recognition:** Bot names are given to the recognizer as hints; on Apple devices you can opt in to Apple's more accurate server recognition.
- **Layouts:** a small card, full screen (big orb, large captions) or a small pill. Minimize and expand at any time. Voice keeps running when you open another Bot; click its name to go back.
- **Self-hosted chat models:** Ollama and LM Studio can answer for any Bot (pick them in the Bot's side panel). They run on your computer, so they are also quick in voice mode.

Not tried on real devices yet: model downloads, WebGPU speed, recognition quality and echo behaviour.

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

## 0.7.6 additions
- Replies are spoken sentence by sentence while they stream. Talking over the Bot (or tapping the orb) stops speech and stops the Bot generating.
- iPhone: when the message box is focused and an image is on the clipboard, a "Paste image from clipboard" button appears. The **Talk to my Bot** shortcut (Shortcuts app, Siri, Action Button) opens voice mode with your main Bot.
- Windows: Attach files… in the plus menu, Ctrl+V to paste images, and attachment chips above the message box.

# Notifications, updates and backups (0.7.6)
- **Notifications**: Mac and Windows notify you when a Bot finishes while the app is in the background. The iPhone shows a banner when a Bot finishes in another chat or shortly after you leave the app; it only knows about replies while it is connected (this is not a push service).
- **Updates**: Settings → Updates → *Download update*, then *Restart and install*. Both apps check the download first (size and SHA-256). Mac unpacks the new app next to the current one, verifies its signature, then on restart swaps it in place and reopens it; if the app is in a folder you can't write to, it opens the disk image instead. Windows runs the installer silently, then reopens the app. Restart is blocked while a Bot is replying, and your workspace is kept.
- **Backups**: Settings → Backup (Windows) or Settings → Updates (Mac). Backups are encrypted with your password (PBKDF2-SHA256, 600,000 rounds, AES-256-GCM) and exclude AI sign-ins, API keys and vault secrets. Restore works on the same platform the backup was made on; the current workspace is saved as a safety copy first.
