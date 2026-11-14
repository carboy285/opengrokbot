const test = require('node:test');
const assert = require('node:assert/strict');
const media = require('./media.cjs');

const PNG = Buffer.from('89504e470d0a1a0a', 'hex');
const json = body => new Response(JSON.stringify(body), { headers: { 'content-type': 'application/json' } });
const bytes = (data, type) => new Response(data, { headers: { 'content-type': type } });
function fake(routes) {
  const calls = [];
  const fetcher = async (url, options = {}) => {
    calls.push({ url: String(url), options });
    for (const [match, reply] of routes) if (String(url).includes(match)) return typeof reply === 'function' ? reply(url, options) : reply;
    return new Response('not found', { status: 404 });
  };
  return { fetcher, calls };
}
const noWait = { pause: async () => {} };

test('a provider is chosen by kind and saved keys', () => {
  assert.equal(media.choose('image', 'flux', { flux: 'k', openai: 'k' }), 'flux');
  assert.equal(media.choose('video', 'flux', { flux: 'k', google: 'k' }), 'google', 'Flux makes images only');
  assert.equal(media.choose('video', null, { openai: 'k' }), null);
  assert.equal(media.validModel('black-forest-labs/flux-schnell'), 'black-forest-labs/flux-schnell');
  assert.equal(media.validModel('../../etc'), null);
});

test('OpenAI images come back as base64', async () => {
  const { fetcher, calls } = fake([['/v1/images/generations', json({ data: [{ b64_json: PNG.toString('base64') }] })]]);
  const out = await media.generate({ kind: 'image', provider: 'openai', prompt: 'a red bike', key: 'sk-test', fetcher });
  assert.deepEqual(out.bytes, PNG);
  assert.equal(out.extension, 'png');
  assert.equal(calls[0].options.headers.Authorization, 'Bearer sk-test');
  assert.equal(JSON.parse(calls[0].options.body).model, 'gpt-image-1');
});

test('Google Imagen and Veo, including the video wait and keyed download', async () => {
  const image = fake([[':predict', json({ predictions: [{ bytesBase64Encoded: PNG.toString('base64'), mimeType: 'image/png' }] })]]);
  const picture = await media.generate({ kind: 'image', provider: 'google', prompt: 'a cat', key: 'g-key', fetcher: image.fetcher });
  assert.deepEqual(picture.bytes, PNG);
  assert.equal(image.calls[0].options.headers['x-goog-api-key'], 'g-key');
  let polls = 0;
  const video = fake([
    [':predictLongRunning', json({ name: 'models/veo-3.0-generate-001/operations/op1' })],
    ['/operations/op1', () => json(++polls < 2 ? { done: false } : { done: true, response: { generateVideoResponse: { generatedSamples: [{ video: { uri: 'https://generativelanguage.googleapis.com/v1beta/files/v1:download?alt=media' } }] } } })],
    ['files/v1:download', bytes(Buffer.from('MP4DATA'), 'video/mp4')]
  ]);
  const clip = await media.generate({ kind: 'video', provider: 'google', prompt: 'waves', key: 'g-key', fetcher: video.fetcher, ...noWait });
  assert.equal(clip.bytes.toString(), 'MP4DATA');
  assert.equal(clip.extension, 'mp4');
  assert.equal(video.calls.at(-1).options.headers['x-goog-api-key'], 'g-key', 'the video download needs the key');
});

test('Flux polls until ready and downloads the sample', async () => {
  let polls = 0;
  const { fetcher, calls } = fake([
    ['/v1/flux-pro-1.1', json({ id: 'job1', polling_url: 'https://api.bfl.ai/v1/get_result?id=job1' })],
    ['get_result', () => json(++polls < 3 ? { status: 'Pending' } : { status: 'Ready', result: { sample: 'https://delivery.bfl.ai/x.jpeg' } })],
    ['delivery.bfl.ai', bytes(PNG, 'image/jpeg')]
  ]);
  const out = await media.generate({ kind: 'image', provider: 'flux', prompt: 'mountains', key: 'bfl', fetcher, ...noWait });
  assert.equal(out.extension, 'jpg');
  assert.equal(calls[0].options.headers['x-key'], 'bfl');
  assert.equal(polls, 3);
});

test('Replicate: quick answers, polled answers, and failures', async () => {
  const quick = fake([['/models/black-forest-labs/flux-schnell/predictions', json({ status: 'succeeded', output: ['https://replicate.delivery/a.webp'] })], ['replicate.delivery', bytes(PNG, 'image/webp')]]);
  const out = await media.generate({ kind: 'image', provider: 'replicate', prompt: 'a fox', key: 'r8', fetcher: quick.fetcher });
  assert.equal(out.extension, 'webp');
  assert.equal(quick.calls[0].options.headers.Prefer, 'wait=60');
  let polls = 0;
  const slow = fake([
    ['/models/minimax/video-01/predictions', json({ status: 'starting', urls: { get: 'https://api.replicate.com/v1/predictions/p1' } })],
    ['/v1/predictions/p1', () => json(++polls < 2 ? { status: 'processing' } : { status: 'succeeded', output: 'https://replicate.delivery/v.mp4' })],
    ['replicate.delivery', bytes(Buffer.from('VID'), 'video/mp4')]
  ]);
  assert.equal((await media.generate({ kind: 'video', provider: 'replicate', prompt: 'rain', key: 'r8', fetcher: slow.fetcher, ...noWait })).extension, 'mp4');
  const failed = fake([['/predictions', json({ status: 'failed', error: 'NSFW content detected' })]]);
  await assert.rejects(media.generate({ kind: 'image', provider: 'replicate', prompt: 'x', key: 'r8', fetcher: failed.fetcher }), /NSFW content detected/);
});

test('bad keys, unsafe links and unsupported kinds give plain errors', async () => {
  const rejected = fake([['/v1/images', new Response('{}', { status: 401 })]]);
  await assert.rejects(media.generate({ kind: 'image', provider: 'openai', prompt: 'x', key: 'bad', fetcher: rejected.fetcher }), /rejected the API key/);
  const http = fake([['/v1/images', json({ data: [{ url: 'http://evil.example/x.png' }] })]]);
  await assert.rejects(media.generate({ kind: 'image', provider: 'openai', prompt: 'x', key: 'k', fetcher: http.fetcher }), /unusable link/);
  await assert.rejects(media.generate({ kind: 'video', provider: 'flux', prompt: 'x', key: 'k', fetcher: http.fetcher }), /cannot make this/);
  await assert.rejects(media.generate({ kind: 'image', provider: 'openai', prompt: '', key: 'k', fetcher: http.fetcher }), /Describe the image/);
});

test('file names are short and safe', () => {
  assert.equal(media.fileName('A red bike, at sunset!!', 'png', new Date('2026-11-14T02:03:04Z')), '20261114T020304-a-red-bike-at-sunset.png');
  assert.equal(media.fileName('../../', 'mp4', new Date('2026-11-14T02:03:04Z')), '20261114T020304-media.mp4');
});
