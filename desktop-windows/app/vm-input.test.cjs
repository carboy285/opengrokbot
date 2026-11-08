const test = require('node:test');
const assert = require('node:assert/strict');
const input = require('./vm-input.cjs');

test('input commands run xdotool through a fixed launcher and keep user text as a separate argument', () => {
  const typed = input.type('p@ss; rm -rf / $(x)');
  assert.equal(typed[0], '/bin/sh'); assert.equal(typed[1], '-c'); assert.equal(typed[3], 'sh'); assert.equal(typed[4], 'xdotool');
  assert.ok(!typed[2].includes('rm -rf'), 'The script never contains the text');
  assert.equal(typed.at(-1), 'p@ss; rm -rf / $(x)'); assert.ok(typed.length <= 16);
  assert.deepEqual(input.click(10, 20).slice(5), ['mousemove', '10', '20', 'click', '1']);
  assert.equal(input.click(-1, 5), null); assert.equal(input.click(1.5, 5), null); assert.equal(input.click(99999, 5), null);
  assert.equal(input.type(''), null); assert.equal(input.type('a\0b'), null);
  assert.equal(input.type('x'.repeat(900)).at(-1).length, 500);
  assert.deepEqual(input.key('Return').slice(5), ['key', 'Return']); assert.equal(input.key('ctrl+alt+Delete'), null);
  assert.ok(input.geometry().includes('getdisplaygeometry'));
});

test('screen size is read from guest output and failures are recognised', () => {
  assert.deepEqual(input.parseGeometry('Linux guest exit 0:\n1920 1080\n'), [1920, 1080]);
  assert.equal(input.parseGeometry('Linux guest exit 1:\nxdotool: not found'), null);
  assert.ok(input.failed('Linux guest exit 127:\nsh: xdotool: not found'));
  assert.ok(input.failed("Linux guest exit 1:\nError: Can't open display: :0"));
  assert.ok(!input.failed('Linux guest exit 0:\n1920 1080'));
});
