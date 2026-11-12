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

test('the first spoken chunk can start at a pause instead of waiting for a whole sentence', async () => {
  const { nextChunk } = await load();
  const text = 'I looked at the page you sent me earlier, and then I checked the results';
  assert.equal(nextChunk(text, 0, false).chunk, '');
  assert.deepEqual(nextChunk(text, 0, false, true), { chunk: 'I looked at the page you sent me earlier,', next: 41 });
  assert.equal(nextChunk('Hello there. And more', 0, false, true).chunk, 'Hello there.');
  assert.equal(nextChunk('Short', 0, true).chunk, 'Short');
});

test('splitText keeps every word and respects the limit', async () => {
  const { splitText, maxSpeechLength } = await load();
  const text = 'One two three. Four five six seven. Eight nine ten eleven twelve.';
  const parts = splitText(text, 20);
  assert.deepEqual(parts, ['One two three.', 'Four five six seven.', 'Eight nine ten', 'eleven twelve.']);
  assert.ok(parts.every(part => part.length <= 20));
  assert.equal(parts.join(' '), text);
  assert.deepEqual(splitText('a'.repeat(50), 20).map(part => part.length), [20, 20, 10]);
  assert.deepEqual(splitText('Hello', 190), ['Hello']);
  assert.deepEqual(splitText('   ', 190), []);
  assert.equal(maxSpeechLength('groq'), 190);
  assert.equal(maxSpeechLength('nvidiaNIM'), 400);
  assert.equal(maxSpeechLength('nvidiaCloud'), 400);
  assert.equal(maxSpeechLength('gemini'), Infinity);
  assert.equal(maxSpeechLength('openAI'), Infinity);
});

test('the first chunk can start at a word boundary after a long run without a pause', async () => {
  const { nextChunk } = await load();
  const text = 'so here is a long stretch of words without any pause at all and it keeps going';
  const first = nextChunk(text, 0, false, true);
  assert.ok(first.chunk.length >= 30 && text.startsWith(first.chunk) && first.chunk.endsWith(' '));
  assert.equal(nextChunk('too short to start', 0, false, true).chunk, '');
  assert.equal(nextChunk('I looked at the page you sent me earlier, and then I checked the results', 0, false, true).chunk, 'I looked at the page you sent me earlier,');
});

test('turn-taking waits through trailing words and pauses', async () => {
  const core = await load();
  assert.equal(core.continuesThought('I want to book a trip and'), true);
  assert.equal(core.continuesThought('so um'), true);
  assert.equal(core.continuesThought('Book it for Tuesday,'), true);
  assert.equal(core.continuesThought('What is on my calendar?'), false);
  assert.equal(core.continuesThought('Book the flight'), false);
  assert.ok(core.silenceFor('relaxed') > core.silenceFor('normal') && core.silenceFor('normal') > core.silenceFor('quick'));
});

test('tool steps become short spoken phrases, failures stay quiet', async () => {
  const core = await load();
  assert.equal(core.stepPhrase('Queued message · Calendar Agent'), 'Asking Calendar Agent.');
  assert.equal(core.stepPhrase('Read “Weather” · weather.com'), 'Reading a page.');
  assert.equal(core.stepPhrase('Linux VM result (untrusted context):\n/bin/ls'), 'Running that on the computer.');
  assert.equal(core.stepPhrase('Couldn’t open example.com: timeout'), '');
  assert.match(core.acknowledgement(0.5), /\w/);
  assert.equal(core.resample16k(new Float32Array(48000), 48000).length, 16000);
});

test('speech is made one sentence at a time and starts quickly', async () => {
  const core = await load();
  assert.deepEqual(core.sentences('Sure. I found three cruises! Want the cheapest?'), ['Sure.', 'I found three cruises!', 'Want the cheapest?']);
  assert.deepEqual(core.sentences('Dr. Smith said the 3.5 km walk is fine. Go.'), ['Dr. Smith said the 3.5 km walk is fine.', 'Go.']);
  const quick = core.sentences('The cheapest cruise leaves Galveston on Friday, and it costs about twelve hundred dollars for two.', true);
  assert.equal(quick[0], 'The cheapest cruise leaves Galveston on Friday,');
  assert.equal(quick.length, 2);
});
