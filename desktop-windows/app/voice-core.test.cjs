'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');

const load = () => import('../renderer/voice-core.mjs');
const tone = (seconds, amp, rate = 16000) => new Float32Array(Math.floor(seconds * rate)).fill(amp);
const feed = (vad, seconds, amp, mode = 'listening', rate = 16000) => {
  const events = [];
  for (let i = 0; i < Math.round(seconds * 10); i++) { const event = vad.push(tone(0.1, amp, rate), mode); if (event) events.push(event); }
  return events;
};

test('speakable removes code, links and markdown symbols', async () => {
  const { speakable } = await load();
  assert.equal(speakable('Hello **world**! See https://x.com/a?b=1 now.'), 'Hello world! See link now.');
  assert.equal(speakable('Run:\n```js\nconsole.log(1)\n```\nDone'), 'Run: (code omitted) Done');
  assert.equal(speakable('```unterminated code'), '(code omitted)');
  assert.equal(speakable(null), '');
});

test('encodeWav writes a valid 16 kHz mono header and downsamples', async () => {
  const { encodeWav } = await load();
  const wav = encodeWav(tone(1, 0.5, 48000), 48000);
  const view = new DataView(wav.buffer);
  assert.equal(String.fromCharCode(...wav.slice(0, 4)), 'RIFF');
  assert.equal(view.getUint32(24, true), 16000);
  assert.equal(view.getUint32(40, true), 32000);
  assert.equal(wav.length, 44 + 32000);
  assert.ok(Math.abs(view.getInt16(100, true) - 16384) < 2);
});

test('vad finishes an utterance after a second of silence and ignores noise bursts', async () => {
  const { Vad } = await load();
  const vad = new Vad({ sampleRate: 16000 });
  assert.deepEqual(feed(vad, 1, 0.001), []);
  assert.deepEqual(feed(vad, 0.1, 0.05), []);
  const events = feed(vad, 1.2, 0.001);
  assert.equal(events.length, 0, 'too short to count');
  assert.deepEqual(feed(vad, 1, 0.05), []);
  const done = feed(vad, 1.2, 0.001);
  assert.equal(done.length, 1);
  assert.equal(done[0].type, 'utterance');
  assert.ok(done[0].samples.length / 16000 > 1);
});

test('vad detects talking over the bot only when sustained and loud', async () => {
  const { Vad } = await load();
  const vad = new Vad({ sampleRate: 16000 });
  assert.deepEqual(feed(vad, 0.3, 0.2, 'speaking'), [], 'short burst is ignored');
  feed(vad, 0.1, 0.0, 'speaking');
  assert.deepEqual(feed(vad, 0.3, 0.04, 'speaking'), [], 'quiet echo is ignored');
  const events = feed(vad, 0.5, 0.2, 'speaking');
  assert.equal(events[0].type, 'barge');
  assert.equal(vad.speaking, true);
  const done = [...feed(vad, 0.5, 0.2), ...feed(vad, 1.1, 0)];
  assert.equal(done.at(-1).type, 'utterance');
});

test('nextChunk releases finished sentences only and never splits code blocks', async () => {
  const { nextChunk } = await load();
  assert.deepEqual(nextChunk('Hello there. How are', 0, false), { chunk: 'Hello there.', next: 12 });
  assert.deepEqual(nextChunk('Hello there. How are', 12, false), { chunk: '', next: 12 });
  assert.deepEqual(nextChunk('Hello there. How are you? I', 12, false), { chunk: ' How are you?', next: 25 });
  assert.deepEqual(nextChunk('Hello there. How are', 12, true), { chunk: ' How are', next: 20 });
  assert.deepEqual(nextChunk('Run this. ```js\nx = 1. y = 2. ', 0, false), { chunk: 'Run this. ', next: 10 });
  assert.deepEqual(nextChunk('No end yet', 0, false), { chunk: '', next: 0 });
  assert.deepEqual(nextChunk('Emoji 👋 done. More', 0, false), { chunk: 'Emoji 👋 done.', next: 13 });
  assert.deepEqual(nextChunk('abc', 5, false), { chunk: '', next: 5 });
});
