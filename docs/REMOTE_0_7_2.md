# Remote loading fixes · 0.7.2 (build 10)

The relay's existing access logs showed successful discovery, send, poll and acknowledgment HTTP requests. They do not prove encrypted application responses were decoded or that the workspace appeared on a physical device. The reported PC-to-Mac/phone hang was not reproduced locally; the fixes address concrete failure paths found in the loading code.

- Load a small Bot overview first, then request full conversation history. An overview uses its own revision so it cannot be confused with a full workspace. Authoritative conversations stay on the hosting computer.
- Accept both legacy raw full snapshots and the current snapshot/delta envelope. A mismatched delta requests a full refresh.
- Retry a lost request with the same mailbox ID/payload; command delivery retains its separate stable command ID. State requests stop waiting after 12 seconds of mailbox polling rather than 35 seconds. Individual network calls still have their own network timeouts; this is not a strict wall-clock connection guarantee.
- Preserve errors during retries; never silently change the selected computer after an initial timeout. A bad reply is acknowledged and reported rather than blocking subsequent polls.
- Mac hosts return bounded explicit errors when a valid request format or workspace response cannot be transferred, rather than dropping it and leaving the viewer waiting. Oversized workspaces report a transfer limit.
- Windows provides a Reconnect button, distinguishes approval/retrying/connected stages, and selects the first available Bot when its roster arrives. Sending requires a connected workspace.
- Mac approval wording includes desktop viewers and phones. Approval remains required; encryption and account ownership are unchanged.

## Upgrade and connect

Quit older copies of OpenGrokBot, install **0.7.2** on the host and PC, and reinstall the matching **GrokBot** Xcode target on iPhone with the existing signing team and bundle identifier. Confirm version **0.7.2**, build **10**.

On the hosting Mac/PC, sign into Settings → Computer and enable Allow phone access. On the viewing PC, use This computer to select that host. Compare fingerprints and approve the viewing device on the host. Use Reconnect after updating. On iPhone, sign into the same account and select that same host. The phone controls desktop Bots; it is not a Bot host that a PC can select.

A roster can appear before full history. While the status says loading chat history, the displayed snippet is only a preview. If the full workspace exceeds the encrypted relay limit, the error explains that older conversations must be exported on the host.

No automated tests, syntax checks, UI automation, test database queries or physical-device validation were run, as requested. Existing relay logs were inspected for diagnosis. Installer compilation/packaging is recorded separately and does not establish runtime interoperability.


## Visible local browsers

Bot details → **Open local browser** opens a native browser window on the hosting computer. Mac uses WebKit with a persistent data store identified by Bot UUID; Windows uses a sandboxed Chromium WebContentsView with a persistent session partition identified by Bot UUID. Cookies/logins remain local and separate for each Bot. The existing browse_web tool now navigates and reads that visible local browser instead of Browserbase; the cloud adapter and provider configuration UI were removed. Windows supports HTTP/HTTPS; Mac accepts HTTPS. At most eight browser windows can be open together. Browser permissions/downloads are not automatically granted. Use the window to click, type or sign in manually.

Approved phone and desktop viewers can open the browser on the host and fetch a bounded JPEG still preview over the existing encrypted relay. Views refresh automatically approximately every three seconds while open (with a pause control) and do not provide remote keyboard/mouse control. They are not permanent cloud screenshots. Browser pages are untrusted input; page text is returned with a bounded size and labeled as context.

Implementation references: [WebKit profile data stores](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/) and [Electron persistent sessions](https://www.electronjs.org/docs/latest/api/session).

## Linux VM setup

The user chose Linux guests. In Bot details, install the supported manager using the download link, download the Linux guest asset, then choose the setup action. OpenGrokBot does not silently install a privileged hypervisor or accept OS installer prompts.

- **Mac:** install [UTM](https://mac.getutm.app/) into Applications, download a Linux `.utm` template from the [gallery](https://mac.getutm.app/gallery/) matching the Mac's architecture, and select it. Setup imports the template and duplicates it for this Bot with 2 CPU cores and 4 GB RAM, saves the assigned VM UUID, and opens the UTM console. Disk size comes from the template. Allow macOS's Automation request to control UTM. Failed imports may leave a VM in UTM; inspect it before retrying. The source template is not deleted. [UTM automation reference](https://docs.getutm.app/scripting/reference/).
- **Windows:** install [VirtualBox 7.2+](https://www.virtualbox.org/wiki/Downloads), then select an [Ubuntu 24.04 x64 desktop ISO](https://releases.ubuntu.com/24.04/) or prepared Linux OVA. ISO setup creates a separate 2-core/4-GB VM with a 32-GB VDI, NAT networking, clipboard/drag-and-drop disabled, a random guest login and an unattended-install request with Guest Additions. The installer runs in the visible console and may take several minutes. OpenGrokBot stores the login encrypted with Windows device storage; **Copy guest login** retrieves it for the owner. The VM manager's installation media may also contain guest-install credentials. The temporary password input file is removed after the manager consumes it. OVA imports keep template disk size and credentials. Interrupted setup retains the VM record instead of deleting disks. [VirtualBox command reference](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/vboxmanage.html).

The AI CLI remains on the host. Optional `vm_exec` actions execute a bounded command in the assigned guest only after the owner enables **Allow this Bot to run guest commands**. UTM requires qemu-guest-agent in the Linux guest and can execute as guest root; VirtualBox ISO guests require Guest Additions and the saved guest login. Imported OVAs use their existing logins and do not expose this guest-command toggle. Guest output is untrusted context, not new human approval. A VM console is visible on the host; VM high-frame-rate streaming, remote keyboard/mouse control and installing a separate guest AI agent are not provided. A UTM command that times out may continue inside the guest.

## Recent Bot order

Unpinned Bots sort by the newest chat-open timestamp or message activity, newest first. Chat opens are persisted on the hosting computer and carried in workspace snapshots so phone and desktop viewers converge. Pinned order is preserved. Unused Bots keep their existing relative order. Drag/folder organization remains available, but unpinned recency determines their displayed order.

Browser/VM managers were not launched and guests were not installed in this Linux workspace. VM creation, guest tools, browser isolation and physical-device interoperability were not runtime-tested. Compilation/packaging results are recorded with the release downloads.


## Viewing a hosted browser or VM from another device

After selecting the host through the account workspace switcher, open a Bot’s **Browser** or **VM view** on a viewing Mac/Windows computer. On iPhone, use Bot details → Open/view local browser or View local Linux VM. An open view refreshes an encrypted image roughly every three seconds; it can be paused or manually refreshed. The browser/VM continues running on the selected host. These are periodic views, not an interactive remote desktop or high-frame-rate video stream. Use **Open on host** to launch an already configured browser/VM console.

Windows VM views use VirtualBox’s display framebuffer (`controlvm screenshotpng`), resize the image and remove its temporary PNG after capture. On a hosting Mac, open the assigned UTM VM console, choose **Enable remote VM viewing** in this Bot’s settings, and grant macOS Screen Recording access to OpenGrokBot. ScreenCaptureKit captures only the matching UTM VM window (identified by the per-Bot VM name), never the full host desktop or a fallback window. If the matching console or permission is unavailable, the viewer receives an error explaining the host-side setup. Apple’s screen-capture access requirement is documented in [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit).

Views close or clear when switching accounts/hosts. Large frames are bounded before relay transfer; image capture and guest installation remain unverified on physical hosts.

Packaging completed: https://github.com/carboy285/opengrokbot/actions/runs/41359536522 compiled the iPhone sources and universal Mac app, packaged both desktop installers, and published 0.7.2 from runtime commit `ca2fb49eb97a41bdecf6cafdbad241231fecd55f`. No automated tests, physical-host VM installs or end-to-end remote/browser tests were run.
