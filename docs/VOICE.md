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
