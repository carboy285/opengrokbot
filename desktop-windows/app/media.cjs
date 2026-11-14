'use strict';
// Image and video generation (0.9.7). A Bot asks with an app action; this process calls the provider with the human's
// own key (never shown to the model), saves the result in the Bot's folder, and the chat shows it.

const PROVIDERS = {
  flux: { name: 'Flux (Black Forest Labs)', kinds: ['image'], image: 'flux-pro-1.1', keyHelp: 'https://dashboard.bfl.ai/' },
  google: { name: 'Google (Imagen, Veo)', kinds: ['image', 'video'], image: 'imagen-4.0-generate-001', video: 'veo-3.0-generate-001', keyHelp: 'https://aistudio.google.com/apikey' },
  openai: { name: 'OpenAI images', kinds: ['image'], image: 'gpt-image-1', keyHelp: 'https://platform.openai.com/api-keys' },
  replicate: { name: 'Replicate (many image and video models)', kinds: ['image', 'video'], image: 'black-forest-labs/flux-schnell', video: 'minimax/video-01', keyHelp: 'https://replicate.com/account/api-tokens' }
};
const LIMITS = { image: 25 * 1024 * 1024, video: 200 * 1024 * 1024 };
const MODEL = /^[A-Za-z0-9._-]{1,100}(\/[A-Za-z0-9._-]{1,100})?(:[A-Za-z0-9]{1,100})?$/;

class MediaError extends Error {}
const clip = value => String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, 200);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function validModel(value) { return typeof value === 'string' && MODEL.test(value) ? value : null; }

/** Which provider to use: the one asked for if it has a key and supports the kind, else the first that does. */
function choose(kind, wanted, keys) {
  const ready = Object.keys(PROVIDERS).filter(id => keys[id] && PROVIDERS[id].kinds.includes(kind));
  if (wanted && ready.includes(wanted)) return wanted;
  return ready[0] || null;
}

async function call(fetcher, url, options, label) {
  let response;
  try { response = await fetcher(url, { redirect: 'error', signal: AbortSignal.timeout(120000), ...options }); }
  catch { throw new MediaError(`${label} could not be reached.`); }
  if ([401, 403].includes(response.status)) throw new MediaError(`${label} rejected the API key. Check it in Settings → API Keys.`);
  if (response.status === 402) throw new MediaError(`${label} says the account has no credit left.`);
  if (response.status === 429) throw new MediaError(`${label}’s rate limit was reached. Try again in a minute.`);
  const text = await response.text();
  let body = null; try { body = JSON.parse(text); } catch {}
  if (!response.ok) throw new MediaError(`${label} could not make it: ${clip(body?.error?.message || body?.detail || body?.error || text) || 'HTTP ' + response.status}`);
  if (!body) throw new MediaError(`${label} returned an unsupported response.`);
  return body;
}

/** Downloads a finished file. Only https, only from the provider's own result, within the size limit. */
async function download(fetcher, url, kind, label, headers = {}) {
  let parsed; try { parsed = new URL(url); } catch { throw new MediaError(`${label} returned an unusable link.`); }
  if (parsed.protocol !== 'https:') throw new MediaError(`${label} returned an unusable link.`);
  let response;
  try { response = await fetcher(parsed.href, { headers, redirect: 'follow', signal: AbortSignal.timeout(300000) }); }
  catch { throw new MediaError(`The ${kind} could not be downloaded from ${label}.`); }
  if (!response.ok) throw new MediaError(`The ${kind} could not be downloaded from ${label} (HTTP ${response.status}).`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (!bytes.length || bytes.length > LIMITS[kind]) throw new MediaError(`The ${kind} from ${label} was empty or too large.`);
  return { bytes, type: response.headers.get('content-type') || '' };
}

/** Waits for a long-running job: polls `check` until it returns a value, up to `limit` milliseconds. */
async function waitFor(check, { every = 2000, limit = 300000, label, now = Date.now, pause = sleep }) {
  const end = now() + limit;
  while (now() < end) { const value = await check(); if (value) return value; await pause(every); }
  throw new MediaError(`${label} took too long. Try again or choose a faster model.`);
}

const extensionFor = (type, kind) => /png/.test(type) ? 'png' : /jpe?g/.test(type) ? 'jpg' : /webp/.test(type) ? 'webp' : /webm/.test(type) ? 'webm' : /quicktime|mov/.test(type) ? 'mov' : kind === 'video' ? 'mp4' : 'png';

/**
 * Makes one image or video. Returns { bytes, extension, provider, model }.
 * options: { kind, provider, prompt, key, model, fetcher, now, pause }
 */
async function generate({ kind, provider, prompt, key, model, fetcher = fetch, now, pause }) {
  const info = PROVIDERS[provider];
  if (!info || !info.kinds.includes(kind)) throw new MediaError('That provider cannot make this.');
  if (typeof prompt !== 'string' || !prompt.trim() || prompt.length > 4000) throw new MediaError('Describe the ' + kind + ' in up to 4,000 characters.');
  const chosen = validModel(model) || info[kind], label = info.name.split(' (')[0], wait = { label, now, pause };
  const json = { 'Content-Type': 'application/json' };
  let result;
  if (provider === 'openai') {
    const body = await call(fetcher, 'https://api.openai.com/v1/images/generations', { method: 'POST', headers: { ...json, Authorization: 'Bearer ' + key }, body: JSON.stringify({ model: chosen, prompt, size: '1024x1024', n: 1 }) }, label);
    const item = body.data?.[0];
    if (item?.b64_json) result = { bytes: Buffer.from(item.b64_json, 'base64'), type: 'image/png' };
    else if (item?.url) result = await download(fetcher, item.url, kind, label);
  } else if (provider === 'google' && kind === 'image') {
    const body = await call(fetcher, `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(chosen)}:predict`, { method: 'POST', headers: { ...json, 'x-goog-api-key': key }, body: JSON.stringify({ instances: [{ prompt }], parameters: { sampleCount: 1 } }) }, label);
    const item = body.predictions?.[0];
    if (item?.bytesBase64Encoded) result = { bytes: Buffer.from(item.bytesBase64Encoded, 'base64'), type: item.mimeType || 'image/png' };
  } else if (provider === 'google' && kind === 'video') {
    const start = await call(fetcher, `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(chosen)}:predictLongRunning`, { method: 'POST', headers: { ...json, 'x-goog-api-key': key }, body: JSON.stringify({ instances: [{ prompt }] }) }, label);
    if (typeof start.name !== 'string' || !/^[A-Za-z0-9/._-]+$/.test(start.name)) throw new MediaError(`${label} did not start the video.`);
    const done = await waitFor(async () => {
      const state = await call(fetcher, `https://generativelanguage.googleapis.com/v1beta/${start.name}`, { headers: { 'x-goog-api-key': key } }, label);
      if (state.error) throw new MediaError(`${label} could not make it: ${clip(state.error.message)}`);
      return state.done ? state : null;
    }, { ...wait, every: 5000, limit: 600000 });
    const uri = done.response?.generateVideoResponse?.generatedSamples?.[0]?.video?.uri || done.response?.generatedVideos?.[0]?.video?.uri;
    if (uri) result = await download(fetcher, uri, kind, label, { 'x-goog-api-key': key });
  } else if (provider === 'flux') {
    const start = await call(fetcher, `https://api.bfl.ai/v1/${encodeURIComponent(chosen)}`, { method: 'POST', headers: { ...json, 'x-key': key }, body: JSON.stringify({ prompt, width: 1024, height: 1024 }) }, label);
    const poll = typeof start.polling_url === 'string' && start.polling_url.startsWith('https://') ? start.polling_url : start.id ? `https://api.bfl.ai/v1/get_result?id=${encodeURIComponent(start.id)}` : null;
    if (!poll) throw new MediaError(`${label} did not start the image.`);
    const done = await waitFor(async () => {
      const state = await call(fetcher, poll, { headers: { 'x-key': key } }, label);
      if (['Error', 'Failed', 'Request Moderated', 'Content Moderated'].includes(state.status)) throw new MediaError(`${label} could not make it (${state.status}).`);
      return state.status === 'Ready' ? state : null;
    }, wait);
    if (done.result?.sample) result = await download(fetcher, done.result.sample, kind, label);
  } else if (provider === 'replicate') {
    const [owner, rest] = chosen.split('/');
    if (!owner || !rest) throw new MediaError('Replicate models are written as owner/name, for example black-forest-labs/flux-schnell.');
    const [name, version] = rest.split(':');
    const endpoint = version ? 'https://api.replicate.com/v1/predictions' : `https://api.replicate.com/v1/models/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/predictions`;
    const headers = { ...json, Authorization: 'Bearer ' + key, Prefer: 'wait=60' };
    let state = await call(fetcher, endpoint, { method: 'POST', headers, body: JSON.stringify(version ? { version, input: { prompt } } : { input: { prompt } }) }, label);
    const self = state.urls?.get;
    if (!['succeeded', 'failed', 'canceled'].includes(state.status)) {
      if (typeof self !== 'string' || !self.startsWith('https://api.replicate.com/')) throw new MediaError(`${label} did not start the ${kind}.`);
      state = await waitFor(async () => { const next = await call(fetcher, self, { headers: { Authorization: 'Bearer ' + key } }, label); return ['succeeded', 'failed', 'canceled'].includes(next.status) ? next : null; }, { ...wait, every: kind === 'video' ? 5000 : 2000, limit: kind === 'video' ? 900000 : 300000 });
    }
    if (state.status !== 'succeeded') throw new MediaError(`${label} could not make it: ${clip(state.error) || state.status}`);
    const output = Array.isArray(state.output) ? state.output.find(x => typeof x === 'string') : state.output;
    if (typeof output === 'string') result = await download(fetcher, output, kind, label);
  }
  if (!result?.bytes?.length) throw new MediaError(`${label} finished without a ${kind}.`);
  if (result.bytes.length > LIMITS[kind]) throw new MediaError(`The ${kind} from ${label} is too large.`);
  return { bytes: result.bytes, extension: extensionFor(result.type, kind), provider, model: chosen };
}

/** A short, safe file name from the prompt. */
function fileName(prompt, extension, date = new Date()) {
  const slug = String(prompt).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40) || 'media';
  return `${date.toISOString().replace(/[-:]/g, '').replace(/\..+/, '')}-${slug}.${extension}`;
}

module.exports = { PROVIDERS, MediaError, choose, generate, fileName, validModel, waitFor };
