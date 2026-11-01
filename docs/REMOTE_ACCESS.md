# Connect iPhone to Mac with one account

Use the **0.7.0 desktop app and matching iOS sources together**. The iPhone controls the Mac's existing workspace: Bots, chats, models, memory and running CLI tasks. It never creates or saves a separate phone workspace. Windows 0.7.0 uses the same encrypted account relay; open Windows Settings → Computer to sign in and approve the phone.

## Connect

1. Finish the Mac's AI CLI setup. Optional Composio accounts and credentials stay on the Mac.
2. Open **Mac Settings → Computer → iPhone remote control**. Create an email/password account, confirm the email, and sign in. You can use the same account on your phone; don't create two separate accounts.
3. Phone access starts on sign-in unless you previously turned **Allow phone access** off. If it is off, turn it on in **Settings → Computer**. Keep the Mac awake with OpenGrokBot running.
4. On the iPhone, open **Connect Desktop**, sign into the same account, and find your Mac.
5. The Mac prompts when the phone requests access. Compare the fingerprint in that prompt with the one on the iPhone, then click **Approve phone**. You can also approve it in **Mac Settings → Computer**. The iPhone shows an approval message until the Mac grants access and retries automatically.
6. Its actual Bots and chat history appear automatically when there is one available Mac, even if older offline installations remain registered. A saved Mac is preferred; with multiple available Macs, choose one in **Connect Desktop**. Verify the Mac's fingerprint on the phone too.

This works over Wi-Fi or cellular through Supabase HTTPS. No Tailscale app, Funnel, pairing URL, public IP, port forwarding or local-network permission is required. The Mac no longer starts a local HTTP listener.

## While away

To change a Bot’s avatar, open its side panel on the Mac and click the avatar. Choose a shape and color, generate a random shape/color combination, upload an image, or reset the avatar, then select **Save avatar**. On iPhone, open Bot details and tap the avatar. Changes are saved on the Mac and appear on both devices. Uploaded images are resized before saving and travel through the encrypted relay with the workspace.

The phone reconnects when reopened or when its network returns. During an outage, already loaded chats remain visible and commands are disabled. Sending retries reuse a command ID so an uncertain acknowledgment does not duplicate a user message. The host records recent command receipts across restarts. Work continues on the Mac when you background, disconnect or sign out of the phone.

**Disconnect this iPhone** clears the displayed workspace and host selection; it leaves the Mac's data and work in place. **Revoke** beside a phone on the Mac blocks further control until you approve it again. Turning off **Allow phone access**, signing out on the Mac, sleeping it, or quitting the app makes it unavailable. Disabling access does not stop already running desktop AI work; quitting does.

Closing a Mac window leaves the app running. Reopen its window from the Dock. The app does not keep a sleeping computer awake or wake it remotely.

## Accounts and service configuration

The supplied Apple builds point at the connected Supabase project `kiaenmbtsgoxvfsijzzc`. Email/password authentication is enabled with email confirmation. Google and GitHub buttons appear only when those providers are enabled in Supabase; they use browser sign-in with PKCE. Provider credentials are deliberately left for later configuration.

Supabase's default email service restricts delivery to project-team addresses and has a low send quota. Configure custom SMTP in **Authentication → Email** before offering signup to other people. A third-party SMTP provider may offer a free tier. Do not disable email verification to work around mail delivery restrictions. Supabase and mail/provider limits apply independently of this free app.

For your own deployment, apply `supabase/migrations/202611010001_account_relay.sql`, change the public URL/publishable key in `GrokBot/Core/CloudProtocol.swift`, and add `opengrokbot://auth/callback` to Auth's redirect allowlist. Never embed a service-role key. The migration uses isolated `opengrok_*` tables/functions and preserves other applications' schemas and Auth settings. The existing `luma://auth/callback` was preserved in the connected project. Google/GitHub OAuth app callbacks go to your Supabase project's `/auth/v1/callback`, not directly to the native app.

## What crosses the service

Supabase Auth holds the email account. The device registry holds owner ID, device ID, name, role, public encryption key, availability and heartbeat. Row-level security isolates each account; anonymous users cannot read the registry or execute relay functions. Device keys cannot be replaced through the registration function.

Each installation keeps a Curve25519 private key, approved peer keys, and refresh tokens in device-only Keychain. The Mac must approve each phone locally after fingerprint comparison. Phone requests and Mac replies use Curve25519 key agreement, HKDF-SHA256 and AES-GCM. Routing IDs, direction, account and protocol are authenticated, and an encrypted expiry prevents the relay extending a message's lifetime. Device discovery requires trusting the first fingerprint; later key changes are rejected.

The database sees routing metadata and bounded ciphertext, not chat plaintext, CLI sessions or provider credentials. Packets expire after 90 seconds and are deleted when acknowledged or on subsequent queue activity; expired data is never returned. Queue limits are 40 packets/32 MB per account, 32 registered devices and approximately 5.9 MB of plaintext per encrypted packet. State updates transfer changed entries. This is a polling relay, usually updating within a few seconds; it is not remote screen sharing or a background iOS service.

Only the host can run AI, install/sign into CLIs, configure Composio or manage the local vault. The controller can send/stop/retry, create/delete additional Bots, choose a provider/model, inspect memory and list working files. Voice, file upload, screen sharing, schedules and wake management remain unavailable. The Mac's CLI and Composio permissions still apply to actions initiated from the phone.

## Upgrading from 0.5.0

Account sign-in replaces pairing keys on Apple platforms. Sign in again and approve your phone; old pairing links are not imported. The new Mac build does not invoke Tailscale or change your existing Tailscale configuration. If you enabled a Serve/Funnel route with 0.5.0, disable it from that version before upgrading, or remove that specific app route in Tailscale. Other Tailscale services must be preserved.

For physical iPhone installation, see [Device setup](DEVICE_SETUP.md). Physical-device roaming and live email delivery require your accounts and have not been verified by the automated fixtures; see [Verification](VERIFICATION.md).
