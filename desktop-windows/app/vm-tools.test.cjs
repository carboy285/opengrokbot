const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const tools = require('./vm-tools.cjs');

test('the VM list entry matches the fixture the Mac app is also tested against, and carries both name keys', () => {
  const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, '../../GrokBotTests/Fixtures/vms.json'), 'utf8'));
  const built = [tools.vmListEntry('4C2D6F2E-0A3B-4F57-9D1E-5B7A1C9E8F10', 'Shared VM on Bens-Windows-PC', 'ready')];
  assert.deepEqual(built, fixture);
  for (const key of ['botID', 'botName', 'state']) assert.ok(key in built[0], `0.8.9 and later Mac apps require ${key}`);
  assert.equal(built[0].name, built[0].botName);
});

test('showvminfo output is read into state and Guest Additions level', () => {
  const info = tools.parseVMInfo('name="OpenGrokBot-x"\nVMState="running"\nGuestAdditionsRunLevel=2\nmemory=4096\r\n');
  assert.equal(tools.vmState(info), 'running'); assert.equal(tools.guestRunLevel(info), 2);
  assert.equal(tools.vmState({}), 'unknown'); assert.equal(tools.guestRunLevel({}), 0);
});

test('the newest Ubuntu 24.04 desktop ISO and the Windows VirtualBox installer are found with their checksums', () => {
  const sha = c => c.repeat(64);
  const sums = `${sha('a')} *ubuntu-24.04.1-desktop-amd64.iso\n${sha('b')} *ubuntu-24.04.3-desktop-amd64.iso\n${sha('c')} *ubuntu-24.04.3-live-server-amd64.iso\n`;
  assert.deepEqual(tools.pickUbuntuDesktop(sums), { name: 'ubuntu-24.04.3-desktop-amd64.iso', sha256: sha('b') });
  assert.equal(tools.pickUbuntuDesktop('nothing here'), null);
  assert.equal(tools.parseVBoxVersion('7.1.6\n'), '7.1.6'); assert.equal(tools.parseVBoxVersion('<html>'), null);
  const vb = `${sha('d')} *VirtualBox-7.1.6-167084-Win.exe\n${sha('e')} *VirtualBox-7.1.6-167084-OSX.dmg\n${sha('f')} *VirtualBox-7.0.20-163906-Win.exe\n`;
  assert.deepEqual(tools.pickVBoxWindows(vb, '7.1.6'), { name: 'VirtualBox-7.1.6-167084-Win.exe', sha256: sha('d') });
  assert.equal(tools.pickVBoxWindows(vb, '9.9.9'), null);
});

// The command carries files as base64 so quoting survives VirtualBox's template; decode it to check what lands in the guest.
const decoded = command => command + '\n' + [...command.matchAll(/echo ([A-Za-z0-9+/=]+) \| base64 -d/g)].map(m => Buffer.from(m[1], 'base64').toString('utf8')).join('\n');

test('post-install: auto-login, no lock, passwordless sudo by default; each can be turned off; Xorg always', () => {
  const all = decoded(tools.postInstallCommand());
  assert.match(all, /AutomaticLoginEnable=true/); assert.match(all, /AutomaticLogin=bot/); assert.match(all, /WaylandEnable=false/);
  assert.match(all, /lock-enabled=false/); assert.match(all, /idle-delay=uint32 0/); assert.match(all, /dconf update/);
  assert.match(all, /bot ALL=\(ALL\) NOPASSWD:ALL/); assert.match(all, /chmod 440/); assert.match(all, /visudo -cf/);
  const none = decoded(tools.postInstallCommand({ autoLogin: false, noLock: false, sudo: false }));
  assert.doesNotMatch(none, /AutomaticLogin/); assert.doesNotMatch(none, /lock-enabled/); assert.doesNotMatch(none, /NOPASSWD/);
  assert.match(none, /WaylandEnable=false/);
  assert.doesNotMatch(decoded(tools.postInstallCommand(false)), /AutomaticLogin/, 'older boolean form still works');
  assert.doesNotMatch(tools.postInstallCommand(), /'/, 'no quotes to break the installer template');
});

test('post-install: the repair script fixes cdrom sources and dpkg, installs and starts guest tools, and runs at boot until it works', () => {
  const all = decoded(tools.postInstallCommand());
  const script = tools.GUEST_SETUP_SCRIPT;
  assert.ok(script.indexOf('cdrom') < script.indexOf('apt-get update'), 'cdrom source removed before apt-get update');
  assert.ok(script.indexOf('dpkg --configure -a') < script.indexOf('apt-get install -y virtualbox-guest-utils'));
  assert.match(script, /virtualbox-guest-utils virtualbox-guest-x11 xdotool/);
  assert.match(script, /systemctl start virtualbox-guest-utils/); assert.match(script, /systemctl enable virtualbox-guest-utils/);
  assert.match(all, /ConditionPathExists=!\/var\/lib\/opengrokbot\/guest-tools-ok/);
  assert.match(all, /multi-user\.target\.wants\/opengrokbot-guest-setup\.service/);
  assert.match(script, /is-active --quiet virtualbox-guest-utils; then touch/);
});

test('watcher: every guest state leads somewhere, nothing waits forever', () => {
  const M = 60000, base = { vmState: 'running', level: 0, now: 100 * M, levelSince: 100 * M, readySince: 0, offPolls: 0, testingSince: 0, rebooted: false };
  const d = s => tools.watchDecision({ ...base, ...s });
  assert.equal(d({}).action, 'wait'); assert.match(d({}).progress, /Installing Ubuntu/);
  assert.equal(d({ vmState: 'poweroff', offPolls: 1 }).action, 'wait');
  for (const vmState of ['poweroff', 'saved', 'aborted']) assert.equal(d({ vmState, offPolls: 3 }).action, 'start');
  assert.match(d({ level: 1, levelSince: 95 * M }).progress, /Finishing guest tools/);
  assert.equal(d({ level: 1, levelSince: 79 * M }).action, 'reboot', 'stuck at run level 1 (driver only): restart so the boot repair runs');
  assert.equal(d({ level: 1, levelSince: 50 * M, rebooted: true }).action, 'fail');
  assert.equal(d({ level: 1, levelSince: 70 * M, rebooted: true }).action, 'wait');
  assert.equal(d({ level: 2, readySince: 100 * M - 10000 }).action, 'wait', 'waits 30 s after guest tools start');
  assert.equal(d({ level: 2, readySince: 99 * M }).action, 'test');
  assert.equal(d({ level: 3, readySince: 99 * M, testingSince: 95 * M }).action, 'test', 'keeps testing for up to 10 minutes');
  assert.equal(d({ level: 2, readySince: 80 * M, testingSince: 89 * M }).action, 'reboot', 'reboots once before failing');
  const failed = d({ level: 2, readySince: 80 * M, testingSince: 89 * M, rebooted: true, lastError: 'The specified user was not able to logon on guest' });
  assert.equal(failed.action, 'fail'); assert.equal(failed.progress, 'The saved guest password no longer matches. Click Update guest password.');
});

test('guest errors: duplicate sessions retry, a wrong password does not, lock errors are recognised', () => {
  assert.ok(tools.retryableGuest('VBoxManage: error: VERR_DUPLICATE (0x80bb0005) GuestSession'));
  assert.ok(!tools.retryableGuest('The specified user was not able to logon on guest'));
  assert.ok(tools.lockedError('The machine is already locked by a session (VBOX_E_INVALID_OBJECT_STATE)'));
  assert.equal(tools.friendlyGuestError('random'), '');
});

test('clipboard mode is read from the saved .vbox file', () => {
  assert.equal(tools.savedClipboardMode('<Hardware><Clipboard mode="HostToGuest"/></Hardware>'), 'HostToGuest');
  assert.equal(tools.savedClipboardMode('<Hardware/>'), 'Disabled');
  assert.deepEqual(Object.keys(tools.CLIPBOARD_MODES), ['disabled', 'hosttoguest', 'guesttohost', 'bidirectional']);
});
