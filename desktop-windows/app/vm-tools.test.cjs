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

test('the post-install command turns on auto-login and Xorg only when asked, and always adds xdotool', () => {
  assert.match(tools.postInstallCommand(true), /AutomaticLoginEnable=true/); assert.match(tools.postInstallCommand(true), /AutomaticLogin=bot/);
  assert.doesNotMatch(tools.postInstallCommand(false), /AutomaticLogin/);
  for (const on of [true, false]) { assert.match(tools.postInstallCommand(on), /WaylandEnable=false/); assert.match(tools.postInstallCommand(on), /xdotool/); }
});
