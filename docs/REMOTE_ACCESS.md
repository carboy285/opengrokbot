# Control your desktop from iPhone

The iPhone app is a controller for your Mac or Windows app. Bots, chat history, memories, model settings, working files, credentials, CLI sessions and running work stay on the desktop. The phone reads the host’s state and sends commands to that same workspace. It does not create an independent local Bot workspace.

Use the 0.5.0 desktop and iOS sources together. Older 0.4.0 installers do not include the remote host.

## Pair

1. Finish AI CLI setup in the desktop app. Optional Composio accounts are connected on the host and remain available to its Bots when you chat from the phone.
2. Open desktop **Settings → Computer → iPhone remote control**.
3. Choose a connection method below and select **Enable remote access**.
4. Select **Copy pairing link**. Privately transfer it to your iPhone. Open the link on the phone, or paste it into **Connect Desktop** in the iOS app, then select **Connect to desktop**.
5. Allow local-network access on your devices if using Wi-Fi. The phone shows the actual host name after a successful authenticated connection.

Treat the pairing link like a password: it controls your desktop workspace. The host stores its random pairing key in macOS Keychain or Windows encrypted device storage; the iPhone stores its connection in device-only Keychain. The key is in the pairing link’s fragment, not an HTTP URL query or access log. Every API request requires its bearer key. **Revoke phones / new key** invalidates existing phones; copy a new link to pair again.

## Tailscale private access

Install Tailscale on both devices and join the same tailnet. Leave it connected on your iPhone so the same HTTPS address works on Wi-Fi and cellular. The desktop app attempts to configure an unused dedicated HTTPS port, **8443**, forwarding to its loopback host on **48291**. It checks existing routes and refuses to overwrite another service.

If setup requires authorization or the CLI cannot be found, the app shows a command to run in Terminal:

```text
tailscale serve --bg --https=8443 http://127.0.0.1:48291
```

Complete Tailscale’s setup and enter the resulting `https://your-computer.your-tailnet.ts.net:8443` base address in the desktop app. Select **Save address**, then copy the pairing link. Use the host’s real address, not this example. If port 8443 already hosts another service, configure a separate HTTPS proxy yourself and choose **My HTTPS proxy**; do not replace that service.

See [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve). Its background configuration persists across Tailscale restarts. The app removes only the port route that still points at its own local service when you disable it; it never resets all Serve configuration.

## Tailscale Funnel

Funnel provides public HTTPS, still protected by the app’s pairing key. The phone does not need Tailscale. The host needs a compatible Tailscale installation and permission to use Funnel; on Mac, Tailscale documents the need for an open-source application variant rather than the Mac App Store build.

```text
tailscale funnel --bg --https=8443 http://127.0.0.1:48291
```

Follow Tailscale’s authorization flow if asked. Do not manually convert unrelated services to Funnel. See [Funnel requirements and limitations](https://tailscale.com/docs/features/tailscale-funnel), including supported ports, HTTPS, tailnet policy, and bandwidth limits. Actual tailnet/Funnel access depends on your account and network and has not been exercised with a user account in this implementation workspace.

## Wi-Fi or private IP

Choose **Wi-Fi / private IP** and enable access. The host suggests a private IPv4 address on port 48291; replace it with the correct address if the computer has multiple network interfaces. Both devices must be able to reach that address, and the desktop firewall must allow the app on the trusted local network. Guest Wi-Fi often isolates devices.

Direct HTTP over Wi-Fi is unencrypted. Use only a trusted network. The client accepts direct HTTP only for private/local addresses, including Tailscale’s address range; public hosts require HTTPS. Private IP addresses may change with DHCP, so Tailscale or a stable HTTPS proxy is preferable for roaming. The iOS transport settings permit local names and private IP ranges, rather than disabling HTTPS requirements globally; [Apple documents the IP/CIDR exceptions](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsexceptiondomains).

## Your own HTTPS proxy

Forward your proxy’s root to `http://127.0.0.1:48291`, preserve the Authorization header, and enter its HTTPS base address. The proxy must present a trusted certificate matching its host. Certificate validation stays enabled, and the client refuses redirects so the pairing key cannot be forwarded to another host. Subpath deployments are not supported in this version.

## While away

The host must be awake, online, and running OpenGrokBot. Closing or backgrounding the iPhone does not stop desktop work. The phone reconnects and loads the latest host state when reopened or when its network returns; stale chats remain visible during a temporary outage, with commands disabled until reconnected. Retrying a send whose acknowledgment was lost reuses its request ID to avoid duplicating the user message.

With remote access enabled on Windows, closing the app window hides it in the system tray and keeps hosting. Use the tray’s **Quit and stop host** to quit. On Mac, leave the app running; quitting it stops the host and its owned CLI processes. Disconnecting the phone leaves all desktop data in place. Disable remote access on the desktop to stop the API, or rotate its key to revoke phones.

The phone can send/stop/retry, create/delete additional Bots, select a Bot’s active provider/model, inspect memory, and list its real working files. Initial CLI installation/sign-in, Composio project setup, and device vault management stay on the desktop. Voice, file attachment upload, remote screen sharing, and power/wake management are not implemented.
