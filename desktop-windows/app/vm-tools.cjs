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

/** What the installer should run inside the new system: sign in automatically, use Xorg (so remote clicking works) and add xdotool. */
function postInstallCommand(autoLogin) {
  const parts = [];
  if (autoLogin) parts.push("mkdir -p /etc/gdm3 && printf '\\n[daemon]\\nAutomaticLoginEnable=true\\nAutomaticLogin=bot\\nWaylandEnable=false\\n' >> /etc/gdm3/custom.conf");
  else parts.push("mkdir -p /etc/gdm3 && printf '\\n[daemon]\\nWaylandEnable=false\\n' >> /etc/gdm3/custom.conf");
  parts.push('DEBIAN_FRONTEND=noninteractive apt-get install -y xdotool || true');
  return parts.join('; ');
}

module.exports = { vmListEntry, parseVMInfo, vmState, guestRunLevel, pickUbuntuDesktop, parseVBoxVersion, pickVBoxWindows, HYPERVISOR_NOTE, postInstallCommand };
