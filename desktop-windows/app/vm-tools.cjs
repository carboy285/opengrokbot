'use strict';
/** Pure helpers for the shared VM (no Electron, so they can be tested anywhere). */

/** The entry the VM list endpoint returns. `name` stays for older apps that still read it; `botName` is what 0.8.9 and later read. */
function vmListEntry(botID, displayName, state) {
  const label = String(displayName || 'Shared VM');
  return { botID, name: label, botName: label, state: state || 'ready' };
}

/** `VBoxManage showvminfo --machinereadable` as an object. Values lose their surrounding quotes. */
function parseVMInfo(text) {
  const info = {};
  for (const line of String(text || '').split(/\r?\n/)) {
    const match = /^([^=]+)=(.*)$/.exec(line.trim()); if (!match) continue;
    info[match[1].replace(/^"|"$/g, '')] = match[2].replace(/^"|"$/g, '');
  }
  return info;
}
const vmState = info => info.VMState || 'unknown';
const guestRunLevel = info => Number(info.GuestAdditionsRunLevel || 0) || 0;

/** The Ubuntu 24.04 desktop ISO line in a SHA256SUMS file: { name, sha256 } or null. */
function pickUbuntuDesktop(sums) {
  const lines = String(sums || '').split(/\r?\n/);
  const found = [];
  for (const line of lines) {
    const match = /^([a-f0-9]{64})\s+\*?(ubuntu-24\.04(?:\.\d+)?-desktop-amd64\.iso)\s*$/i.exec(line.trim());
    if (match) found.push({ name: match[2], sha256: match[1].toLowerCase() });
  }
  found.sort((a, b) => b.name.localeCompare(a.name, undefined, { numeric: true }));
  return found[0] || null;
}

/** LATEST-STABLE.TXT holds a version such as 7.1.6. */
function parseVBoxVersion(text) { const match = /^(\d+\.\d+\.\d+)\s*$/.exec(String(text || '').trim()); return match ? match[1] : null; }

/** The Windows installer line in VirtualBox's SHA256SUMS: { name, sha256 } or null. */
function pickVBoxWindows(sums, version) {
  for (const line of String(sums || '').split(/\r?\n/)) {
    const match = /^([a-f0-9]{64})\s+\*?(VirtualBox-(\d+\.\d+\.\d+)-\d+-Win\.exe)\s*$/i.exec(line.trim());
    if (match && match[3] === version) return { name: match[2], sha256: match[1].toLowerCase() };
  }
  return null;
}

/** Windows' own hypervisor (Hyper-V, Memory Integrity) makes VirtualBox use a slower path and can freeze the Ubuntu installer. */
const HYPERVISOR_NOTE = 'This PC runs Windows’ own hypervisor (Hyper-V or Memory Integrity), so the VM will run slowly. For better speed, turn off Hyper-V / Virtual Machine Platform / Memory Integrity in Windows Features and restart.';

/**
 * Runs inside the guest at every boot until the VirtualBox guest service is running, so a failed or interrupted
 * install repairs itself without a terminal. Ubuntu's own virtualbox-guest-utils works with a 7.x host; the
 * Guest Additions ISO from Windows VirtualBox builds may have no Linux installer, so it is not used.
 */
const GUEST_SETUP_SCRIPT = `#!/bin/sh
# OpenGrokBot guest tools repair. Safe to run many times.
export DEBIAN_FRONTEND=noninteractive
mkdir -p /var/lib/opengrokbot
sed -i -E 's|^(deb .*cdrom:.*)$|# \\1|' /etc/apt/sources.list 2>/dev/null || true
for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do [ -f "$f" ] && grep -qiE 'cdrom|file:/cdrom' "$f" && mv "$f" "$f.disabled"; done
dpkg --configure -a || true
apt-get -f install -y || true
for i in 1 2 3 4 5; do apt-get update && break; sleep 20; done
apt-get install -y virtualbox-guest-utils virtualbox-guest-x11 xdotool || apt-get install -y virtualbox-guest-utils
systemctl enable virtualbox-guest-utils 2>/dev/null || true
systemctl start virtualbox-guest-utils 2>/dev/null || true
if systemctl is-active --quiet virtualbox-guest-utils; then touch /var/lib/opengrokbot/guest-tools-ok; fi
`;

const GUEST_SETUP_UNIT = `[Unit]
Description=OpenGrokBot guest tools repair
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/opengrokbot/guest-tools-ok

[Service]
Type=oneshot
ExecStart=/bin/sh /usr/local/sbin/opengrokbot-guest-setup.sh
TimeoutStartSec=1800

[Install]
WantedBy=multi-user.target
`;

/**
 * Lets the app give the bot account a new password without knowing the old one: the host puts a SHA-512 crypt hash
 * (never the password itself) in the guest property below, and this runs as root every 20 s to apply and clear it.
 */
const PASSWORD_RESET_SCRIPT = `#!/bin/sh
P=/OpenGrokBot/NewPasswordHash
H=$(VBoxControl --nologo guestproperty get $P 2>/dev/null | sed -n 's/^Value: //p')
[ -n "$H" ] || exit 0
case "$H" in '$6$'*) usermod -p "$H" bot && VBoxControl --nologo guestproperty set /OpenGrokBot/PasswordResetDone "$(date +%s)" ;; esac
VBoxControl --nologo guestproperty delete $P
`;
const PASSWORD_RESET_UNITS = {
  service: `[Unit]\nDescription=OpenGrokBot guest password reset\n\n[Service]\nType=oneshot\nExecStart=/bin/sh /usr/local/sbin/opengrokbot-password-reset.sh\n`,
  timer: `[Unit]\nDescription=OpenGrokBot guest password reset check\n\n[Timer]\nOnBootSec=30\nOnUnitActiveSec=20\nAccuracySec=5\n\n[Install]\nWantedBy=timers.target\n`,
};

const NO_LOCK_DCONF = `[org/gnome/desktop/screensaver]
lock-enabled=false
idle-activation-enabled=false

[org/gnome/desktop/session]
idle-delay=uint32 0
`;

const b64 = text => Buffer.from(text, 'utf8').toString('base64');
const writeFileCommand = (file, text, mode) => `echo ${b64(text)} | base64 -d > ${file}` + (mode ? ` && chmod ${mode} ${file}` : '');

/**
 * What the unattended installer runs inside the new system. Options (all default on):
 * autoLogin (GDM signs in as bot), noLock (no screen lock or idle lock), sudo (bot uses sudo without a password).
 * Xorg is always used because VirtualBox and remote clicking work better there than on Wayland.
 */
function postInstallCommand(options = {}) {
  const opts = typeof options === 'boolean' ? { autoLogin: options } : options;
  const autoLogin = opts.autoLogin !== false, noLock = opts.noLock !== false, sudo = opts.sudo !== false;
  const gdm = '\n[daemon]\n' + (autoLogin ? 'AutomaticLoginEnable=true\nAutomaticLogin=bot\n' : '') + 'WaylandEnable=false\n';
  const parts = [
    'mkdir -p /etc/gdm3 /usr/local/sbin /etc/sudoers.d /etc/systemd/system/multi-user.target.wants /etc/systemd/system/timers.target.wants',
    // Replaces GDM's settings file (Ubuntu ships it with only comments) so there is exactly one [daemon] section.
    writeFileCommand('/etc/gdm3/custom.conf', '# Written by OpenGrokBot\n' + gdm),
    writeFileCommand('/usr/local/sbin/opengrokbot-guest-setup.sh', GUEST_SETUP_SCRIPT, '755'),
    writeFileCommand('/etc/systemd/system/opengrokbot-guest-setup.service', GUEST_SETUP_UNIT, '644'),
    'ln -sf /etc/systemd/system/opengrokbot-guest-setup.service /etc/systemd/system/multi-user.target.wants/opengrokbot-guest-setup.service',
    writeFileCommand('/usr/local/sbin/opengrokbot-password-reset.sh', PASSWORD_RESET_SCRIPT, '700'),
    writeFileCommand('/etc/systemd/system/opengrokbot-password-reset.service', PASSWORD_RESET_UNITS.service, '644'),
    writeFileCommand('/etc/systemd/system/opengrokbot-password-reset.timer', PASSWORD_RESET_UNITS.timer, '644'),
    'ln -sf /etc/systemd/system/opengrokbot-password-reset.timer /etc/systemd/system/timers.target.wants/opengrokbot-password-reset.timer',
  ];
  if (noLock) parts.push('mkdir -p /etc/dconf/profile /etc/dconf/db/local.d', writeFileCommand('/etc/dconf/profile/user', 'user-db:user\nsystem-db:local\n'), writeFileCommand('/etc/dconf/db/local.d/00-nolock', NO_LOCK_DCONF), '(dconf update || true)');
  if (sudo) parts.push(writeFileCommand('/etc/sudoers.d/90-bot-nopasswd', 'bot ALL=(ALL) NOPASSWD:ALL\n', '440') + ' && (visudo -cf /etc/sudoers.d/90-bot-nopasswd || rm -f /etc/sudoers.d/90-bot-nopasswd)');
  parts.push('(/bin/sh /usr/local/sbin/opengrokbot-guest-setup.sh || true)');
  return parts.join(' ; ');
}

const MINUTE = 60000;
/**
 * The setup watcher's next move, from what VirtualBox reports. Pure so every case can be tested.
 * s: { vmState, level, now, levelSince (when the run level last changed), readySince (when level first reached 2),
 *      offPolls, testingSince, rebooted, lastError }
 * Returns { action: 'wait' | 'start' | 'test' | 'reboot' | 'fail', state, progress }.
 */
function watchDecision(s) {
  const running = s.vmState === 'running';
  if (!running) {
    if (['poweroff', 'saved', 'aborted', 'paused'].includes(s.vmState) && s.offPolls >= 3) return { action: 'start', state: 'installing', progress: 'Starting the VM again…' };
    return { action: 'wait', state: 'installing', progress: s.vmState === 'unknown' ? 'Waiting for VirtualBox…' : 'Waiting for the VM to start…' };
  }
  if (s.level <= 0) return { action: 'wait', state: 'installing', progress: 'Installing Ubuntu (this takes a while)…' };
  if (s.level === 1) {
    const stuck = s.now - s.levelSince;
    if (stuck > 20 * MINUTE && !s.rebooted) return { action: 'reboot', state: 'installing', progress: 'Guest tools did not start; restarting the VM so it can repair itself…' };
    if (stuck > 45 * MINUTE) return { action: 'fail', state: 'failed', progress: 'The VM started but its guest tools never came up. Check the VM has internet access, then press Retry.' };
    return { action: 'wait', state: 'installing', progress: 'Finishing guest tools…' };
  }
  if (s.now - s.readySince < 30000) return { action: 'wait', state: 'verifying', progress: 'Guest tools started; waiting a moment before testing…' };
  if (s.testingSince && s.now - s.testingSince > 10 * MINUTE) {
    if (!s.rebooted) return { action: 'reboot', state: 'verifying', progress: 'Test commands keep failing; restarting the VM once and trying again…' };
    return { action: 'fail', state: 'failed', progress: friendlyGuestError(s.lastError) || 'Test commands keep failing. Press Retry.' };
  }
  return { action: 'test', state: 'verifying', progress: 'Checking that commands work in the VM…' };
}

/** A plain-English line for the guest errors seen on real machines, or '' for anything else. */
function friendlyGuestError(text) {
  const message = String(text || '');
  if (/not able to logon|VERR_AUTHENTICATION_FAILURE|logon failure/i.test(message)) return 'The saved guest password no longer matches. Click Update guest password.';
  if (/VERR_DUPLICATE/.test(message)) return 'VirtualBox reported a duplicate guest session. It usually clears after a moment; press Retry.';
  if (/already locked|VBOX_E_INVALID_OBJECT_STATE/i.test(message)) return 'VirtualBox is still busy with the VM. Wait a few seconds and try again.';
  if (/VERR_NOT_FOUND|Guest Additions are not installed|GuestAdditionsRunLevel/i.test(message)) return 'The VM’s guest tools are not running yet.';
  return '';
}
const retryableGuest = text => /VERR_DUPLICATE|VERR_TIMEOUT|VERR_NOT_FOUND|session/i.test(String(text || '')) && !/not able to logon|AUTHENTICATION/i.test(String(text || ''));
const lockedError = text => /already locked|VBOX_E_INVALID_OBJECT_STATE|is locked/i.test(String(text || ''));

/** The clipboard mode saved in a .vbox file (not the running value). */
function savedClipboardMode(vboxXml) { const match = /<Clipboard\b[^>]*\bmode="([^"]+)"/i.exec(String(vboxXml || '')); return match ? match[1] : 'Disabled'; }
const CLIPBOARD_MODES = { disabled: 'Disabled', hosttoguest: 'HostToGuest', guesttohost: 'GuestToHost', bidirectional: 'Bidirectional' };

module.exports = { vmListEntry, parseVMInfo, vmState, guestRunLevel, pickUbuntuDesktop, parseVBoxVersion, pickVBoxWindows, HYPERVISOR_NOTE, postInstallCommand, GUEST_SETUP_SCRIPT, PASSWORD_RESET_SCRIPT, watchDecision, friendlyGuestError, retryableGuest, lockedError, savedClipboardMode, CLIPBOARD_MODES };
