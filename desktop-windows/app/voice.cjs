'use strict';
// Optional cloud speech for the Windows app. Network calls run here in the main process (the renderer CSP blocks them).
// Keys are stored encrypted by main.cjs; this module only receives them for a single request.

const PROVIDERS = new Set(['groq', 'openAI', 'elevenLabs']);

class VoiceError extends Error {}

async function check(response, provider) {
  if (response.ok) return response;
  if (response.status === 401 || response.status === 403) throw new VoiceError(`${provider} rejected the key. Check it in Settings → Voice.`);
  if (response.status === 429) throw new VoiceError(`${provider} free quota or rate limit reached.`);
  throw new VoiceError(`${provider} returned an error (${response.status}).`);
}

async function transcribe({ provider, key, wav, fetchImpl = fetch }) {
  if (!PROVIDERS.has(provider) || !key) throw new VoiceError('Choose a speech provider and add its key in Settings → Voice.');
  if (!Buffer.isBuffer(wav) || wav.length < 1000 || wav.length > 10_000_000) throw new VoiceError('Invalid audio.');
  const form = new FormData();
  form.append('file', new Blob([wav], { type: 'audio/wav' }), 'speech.wav');
  let url, headers;
  if (provider === 'elevenLabs') { url = 'https://api.elevenlabs.io/v1/speech-to-text'; headers = { 'xi-api-key': key }; form.append('model_id', 'scribe_v1'); }
  else {
    url = provider === 'groq' ? 'https://api.groq.com/openai/v1/audio/transcriptions' : 'https://api.openai.com/v1/audio/transcriptions';
    headers = { Authorization: `Bearer ${key}` };
    form.append('model', provider === 'groq' ? 'whisper-large-v3-turbo' : 'whisper-1'); form.append('response_format', 'json');
  }
  const response = await check(await fetchImpl(url, { method: 'POST', headers, body: form, signal: AbortSignal.timeout(30000) }), provider);
  const body = await response.json();
  return typeof body.text === 'string' ? body.text.trim() : '';
}

async function synthesize({ provider, key, text, voiceID, fetchImpl = fetch }) {
  if (!['openAI', 'elevenLabs'].includes(provider) || !key) throw new VoiceError('This provider cannot speak replies.');
  if (typeof text !== 'string' || !text.trim() || text.length > 4500) throw new VoiceError('Invalid text.');
  let url, headers, body;
  if (provider === 'openAI') {
    url = 'https://api.openai.com/v1/audio/speech'; headers = { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
    body = JSON.stringify({ model: 'tts-1', voice: 'alloy', input: text, response_format: 'mp3' });
  } else {
    const id = String(voiceID || '21m00Tcm4TlvDq8ikWAM');
    if (!/^[A-Za-z0-9]{8,40}$/.test(id)) throw new VoiceError('The ElevenLabs voice ID looks invalid.');
    url = `https://api.elevenlabs.io/v1/text-to-speech/${id}?output_format=mp3_44100_64`; headers = { 'xi-api-key': key, 'Content-Type': 'application/json' };
    body = JSON.stringify({ text, model_id: 'eleven_flash_v2_5' });
  }
  const response = await check(await fetchImpl(url, { method: 'POST', headers, body, signal: AbortSignal.timeout(45000) }), provider);
  return Buffer.from(await response.arrayBuffer());
}

module.exports = { transcribe, synthesize, VoiceError, PROVIDERS };
