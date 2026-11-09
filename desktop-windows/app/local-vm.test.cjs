'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const Module = require('node:module');
// local-vm.cjs imports electron at load time; stub it (safeStorage just base64s) so the VirtualBox logic runs under plain Node.
const original = Module._load;
Module._load = function (request, ...rest) {
  if (request === 'electron') return { safeStorage: { isEncryptionAvailable: () => true, encryptString: s => Buffer.from('enc:' + s), decryptString: b => b.toString().slice(4) }, nativeImage: {} };
  return original.call(this, request, ...rest);
};
const { LocalVMs } = require('./local-vm.cjs');
Module._load = original;
LocalVMs.wait = async () => {}; LocalVMs.noWatch = true;

/** A LocalVMs whose VBoxManage is a script: handler(args) returns output or throws an error with .detail. */
function harness(handler, records = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ogb-vm-'));
  const vms = new LocalVMs({ getBot: id => ({ id, name: 'Grok Bot' }), load: async () => records, save: async () => {}, root });
  vms.calls = [];
  vms.executable = async () => 'VBoxManage.exe';
  vms.hypervisorPresent = async () => true;
  vms.run = async args => { vms.calls.push(args); return handler(args, vms.calls); };
  return vms;
}
const fail = detail => { const error = new Error('VirtualBox reported a problem. ' + detail); error.detail = detail; throw error; };
const ID = 'bot-1', record = extra => ({ [ID]: { name: 'OpenGrokBot-bot-1', state: 'ready', username: 'bot', password: Buffer.from('enc:pw').toString('base64'), commandsEnabled: true, ...extra } });

test('open: a VM that is already running is not started again', async () => {
  const vms = harness(args => args[0] === 'showvminfo' ? 'VMState="running"\n' : '', record());
  await vms.open(ID);
  assert.ok(!vms.calls.some(a => a[0] === 'startvm'));
});

test('open: "already locked by a session" counts as success when the VM is then running', async () => {
  let started = false;
  const vms = harness(args => {
    if (args[0] === 'showvminfo') return started ? 'VMState="running"\n' : 'VMState="poweroff"\n';
    if (args[0] === 'startvm') { started = true; fail('The machine is already locked by a session (VBOX_E_INVALID_OBJECT_STATE)'); }
    return '';
  }, record());
  await vms.open(ID);
});

test('modifyvm right after power-off is retried while the session lock is released', async () => {
  let tries = 0;
  const vms = harness(args => { if (args[0] === 'modifyvm' && ++tries < 3) fail('already locked (VBOX_E_INVALID_OBJECT_STATE)'); return ''; });
  await vms.modify('vm', ['--clipboard-mode', 'bidirectional']);
  assert.equal(tries, 3);
});

test('a VM deleted outside the app shows as missing, not as a spinner', async () => {
  const vms = harness(args => args[0] === 'showvminfo' ? fail('Could not find a registered machine named OpenGrokBot-bot-1 (VBOX_E_OBJECT_NOT_FOUND)') : '', record({ state: 'installing' }));
  const status = await vms.status(ID);
  assert.equal(status.missing, true); assert.equal(status.state, 'missing');
});

test('Retry shows when setup failed or has been installing for over 20 minutes', async () => {
  const running = args => args[0] === 'showvminfo' ? 'VMState="running"\n' : '';
  assert.equal((await harness(running, record({ state: 'failed' })).status(ID)).canRetry, true);
  assert.equal((await harness(running, record({ state: 'installing', installStartedAt: Date.now() - 21 * 60000 })).status(ID)).canRetry, true);
  assert.equal((await harness(running, record({ state: 'installing', installStartedAt: Date.now() })).status(ID)).canRetry, false);
});

test('guest commands retry VERR_DUPLICATE, pass the password only in a file, and delete that file', async () => {
  let tries = 0, passwordFile;
  const vms = harness(args => {
    if (args[0] === 'guestcontrol') {
      passwordFile = args.find(a => a.startsWith('--passwordfile=')).slice(15);
      assert.equal(fs.readFileSync(passwordFile, 'utf8'), 'pw');
      assert.ok(!args.includes('pw'), 'password never on the command line');
      if (++tries < 2) fail('VERR_DUPLICATE (VBOX_E_IPRT_ERROR 0x80bb0005) GuestSession');
      return 'ok';
    }
    return 'VMState="running"\nGuestAdditionsRunLevel=2\n';
  }, record());
  assert.equal(await vms.guestRun(ID, ['/bin/true']), 'ok');
  assert.equal(tries, 2); assert.ok(!fs.existsSync(passwordFile));
});

test('a wrong guest password is not retried and says what to do', async () => {
  let tries = 0;
  const vms = harness(args => { if (args[0] === 'guestcontrol') { tries++; fail('The specified user was not able to logon on guest'); } return ''; }, record());
  await assert.rejects(vms.guestRun(ID, ['/bin/true']), /saved guest password no longer matches\. Click Update guest password/);
  assert.equal(tries, 1);
});

test('Update guest password saves the new one only after it works', async () => {
  const vms = harness(args => {
    if (args[0] === 'guestcontrol') { const file = args.find(a => a.startsWith('--passwordfile=')).slice(15); if (fs.readFileSync(file, 'utf8') !== 'new') fail('The specified user was not able to logon on guest'); return ''; }
    return 'VMState="running"\nGuestAdditionsRunLevel=2\n';
  }, record({ state: 'failed' }));
  await assert.rejects(vms.updatePassword(ID, 'wrong'), /did not work/);
  assert.equal((await vms.credentials(ID)).password, 'pw');
  await vms.updatePassword(ID, 'new');
  assert.equal((await vms.credentials(ID)).password, 'new'); assert.equal(vms.records[ID].state, 'ready');
});

test('clipboard: shuts down, saves, checks the saved .vbox file, starts again', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ogb-vbox-')), file = path.join(dir, 'vm.vbox');
  let state = 'running', saved = 'HostToGuest';
  const vms = harness(args => {
    if (args[0] === 'showvminfo') { fs.writeFileSync(file, `<Clipboard mode="${saved}"/>`); return `VMState="${state}"\nCfgFile="${file}"\n`; }
    if (args[0] === 'controlvm' && args[2] === 'acpipowerbutton') state = 'poweroff';
    if (args[0] === 'modifyvm') saved = 'Bidirectional';
    if (args[0] === 'startvm') state = 'running';
    return '';
  }, record({ clipboard: 'hosttoguest' }));
  const status = await vms.setClipboard(ID, 'bidirectional');
  assert.equal(status.clipboard, 'bidirectional');
  const order = vms.calls.map(a => a[0] + (a[2] ? ':' + a[2] : ''));
  assert.ok(order.indexOf('controlvm:acpipowerbutton') < order.findIndex(x => x.startsWith('modifyvm')));
  assert.ok(order.findIndex(x => x.startsWith('modifyvm')) < order.findIndex(x => x.startsWith('startvm')));
});

test('a stopped VM is started without a window before a Bot command', async () => {
  let state = 'saved';
  const vms = harness(args => {
    if (args[0] === 'showvminfo') return `VMState="${state}"\nGuestAdditionsRunLevel=${state === 'running' ? 2 : 0}\n`;
    if (args[0] === 'startvm') { assert.deepEqual(args.slice(-2), ['--type', 'headless']); state = 'running'; }
    return 'done';
  }, record());
  assert.equal(await vms.execute(ID, ['/bin/true']), 'done');
});

test('Delete VM unregisters with --delete and forgets the record', async () => {
  const vms = harness(args => args[0] === 'showvminfo' ? 'VMState="poweroff"\n' : '', record());
  await vms.remove(ID);
  assert.ok(vms.calls.some(a => a[0] === 'unregistervm' && a.includes('--delete')));
  assert.equal(vms.records[ID], undefined);
});

test('Reset guest password sends only a SHA-512 hash, waits for the guest, then tests and saves the new password', async () => {
  let done = '', hash = '';
  const vms = harness(args => {
    if (args[0] === 'guestproperty' && args[1] === 'get') return done ? 'Value: ' + done + '\n' : 'No value set!\n';
    if (args[0] === 'guestproperty' && args[1] === 'set') { hash = args[4]; done = '1700000000'; return ''; }
    if (args[0] === 'guestcontrol') return '';
    return 'VMState="running"\nGuestAdditionsRunLevel=2\n';
  }, record());
  await vms.resetPassword(ID);
  const saved = (await vms.credentials(ID)).password;
  assert.match(hash, /^\$6\$[./A-Za-z0-9]{16}\$[./A-Za-z0-9]{86}$/);
  assert.notEqual(saved, 'pw');
  assert.ok(!vms.calls.flat().includes(saved), 'the new password never appears in a VirtualBox command');
  assert.equal(require('./sha512-crypt.cjs').sha512Crypt(saved, hash.split('$')[2]), hash);
});

test('Reset guest password on a VM without the helper explains what to do and clears the request', async () => {
  const vms = harness(args => args[0] === 'guestproperty' && args[1] === 'get' ? 'No value set!\n' : 'VMState="running"\nGuestAdditionsRunLevel=2\n', record());
  await assert.rejects(vms.resetPassword(ID), /cannot reset it themselves/);
  assert.ok(vms.calls.some(a => a[0] === 'guestproperty' && a[1] === 'delete'));
  assert.equal((await vms.credentials(ID)).password, 'pw');
});
