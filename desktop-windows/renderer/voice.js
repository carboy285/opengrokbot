import { Vad, encodeWav, maxSpeechLength, nextChunk, rms, speakable, splitText } from './voice-core.mjs';

// Hands-free voice mode for Windows.
// Listening needs a cloud key (Groq has a free tier) because Electron has no built-in speech recognition.
// Speaking uses the free Windows voices unless you pick OpenAI or ElevenLabs in Settings → Voice.

const el = (tag, className = '', text = '') => { const node = document.createElement(tag); if (className) node.className = className; if (text) node.textContent = text; return node; };
const toBase64 = bytes => { let binary = ''; for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(binary); };

const icon = body => `<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
const ICONS = {
  gear: icon('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
  chat: icon('<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>'),
  mic: icon('<path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/>'),
  micOff: icon('<line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.1 2.1M15 9.3V4a3 3 0 0 0-5.9-.8"/><path d="M19 10v2a7 7 0 0 1-.1 1.2M5 10v2a7 7 0 0 0 11.7 5.2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/>'),
  close: icon('<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>')
};

export function createVoice({ bridge, result, toast, currentBot, latestReply, sendText, openSettings }) {
  let session = null;

  async function start() {
    if (session) return;
    const bot = currentBot();
    if (!bot) return;
    const settings = await result(bridge.voiceSettings());
    // This Bot's own voice choices win over the app-wide ones. 'apple' is the built-in voice (the Windows voice here).
    const own = bot.voice || {};
    if (own.speaker) settings.speaker = own.speaker === 'apple' ? 'system' : own.speaker;
    if (own.speed) settings.speed = own.speed;
    settings.language = own.language && own.language !== 'auto' ? own.language : (navigator.language || 'en-US');
    if (!settings.keys[settings.transcriber]) {
      toast('Voice needs a listening key. Add a free Groq key in Settings → Voice.');
      openSettings?.(); return;
    }
    let stream;
    try { stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } }); }
    catch { toast('The microphone is blocked. Allow microphone access in Windows privacy settings.'); return; }

    const overlay = el('div', 'voice-overlay'); overlay.setAttribute('role', 'dialog'); overlay.setAttribute('aria-label', `Voice mode with ${bot.name}`);
    const card = el('div', 'voice-card'), top = el('div', 'voice-top');
    const orb = el('button', 'voice-orb'); orb.type = 'button'; orb.setAttribute('aria-label', 'Interrupt the Bot'); orb.append(el('span'), el('span'));
    const wave = el('div', 'voice-wave'); wave.setAttribute('aria-hidden', 'true');
    const bars = Array.from({ length: 32 }, () => { const bar = document.createElement('i'); wave.append(bar); return bar; });
    top.append(orb, wave);
    const line = el('div', 'voice-line'); line.setAttribute('aria-live', 'polite');
    const controls = el('div', 'voice-controls');
    const control = (className, body, label) => { const node = el('button', className); node.type = 'button'; node.innerHTML = body; node.setAttribute('aria-label', label); return node; };
    const gear = control('voice-gear', ICONS.gear, 'Voice settings');
    const chat = control('voice-chat', ICONS.chat, 'Hide captions'); chat.setAttribute('aria-pressed', 'true');
    const mic = control('voice-mic', ICONS.mic, 'Mute microphone'); mic.setAttribute('aria-pressed', 'false');
    const end = control('voice-end', ICONS.close, 'End voice mode');
    controls.append(gear, chat, mic, end);
    const grip = el('div', 'voice-grip'); grip.setAttribute('aria-label', 'Drag to move the voice card'); grip.append(el('span'));
    card.append(grip, top, line, controls); overlay.append(card);
    document.body.append(overlay); end.focus();
    let statusText = 'Listening…', captionText = '', noteText = '', level = 0, frame = 0;
    const renderLine = () => { line.textContent = noteText || captionText || (state.muted ? 'Muted' : statusText); };
    const setNote = text => { noteText = text; renderLine(); };
    const setCaption = text => { captionText = text; renderLine(); };

    const audio = new AudioContext();
    const source = audio.createMediaStreamSource(stream);
    const processor = audio.createScriptProcessor(2048, 1, 1);
    const vad = new Vad({ sampleRate: audio.sampleRate });
    const state = { mode: 'listening', alive: true, cancelSpeech: null, muted: false };
    let queue = [], draining = false, streamDone = false;
    session = { stop };

    const set = (mode, text) => { state.mode = mode; statusText = text; overlay.dataset.mode = mode; renderLine(); };
    set('listening', 'Listening…');

    processor.onaudioprocess = event => {
      if (!state.alive || state.mode === 'thinking' || state.muted) return;
      const chunk = new Float32Array(event.inputBuffer.getChannelData(0));
      level = Math.max(level, Math.min(1, rms(chunk) * 8));
      orb.style.transform = `scale(${1 + level * 0.12})`;
      const heard = vad.push(chunk, state.mode === 'speaking' ? 'speaking' : 'listening');
      if (!heard) return;
      if (heard.type === 'barge') { if (settings.talkOver) { queue = []; state.cancelSpeech?.(); set('listening', 'Listening…'); } else vad.reset(); return; }
      handleUtterance(heard.samples);
    };
    source.connect(processor); processor.connect(audio.destination);

    async function handleUtterance(samples) {
      set('thinking', 'Transcribing…');
      try {
        const wav = toBase64(encodeWav(samples, audio.sampleRate));
        const text = await result(bridge.voiceTranscribe(wav));
        if (!state.alive) return;
        if (!text) { resume(); return; }
        setCaption(text); set('thinking', 'Thinking…');
        const before = latestReply(bot)?.id;
        await sendText(bot, text);
        // Speak finished sentences while the reply is still being written.
        let offset = 0, started = false;
        for (let waited = 0; state.alive && waited < 180000; waited += 40) {
          await new Promise(done => setTimeout(done, 40));
          const reply = latestReply(bot);
          if (!reply || reply.id === before) continue;
          if (started && state.mode !== 'speaking') { if (!reply.finished) bridge.stop?.(bot.id); return; }
          const piece = nextChunk(reply.text, offset, reply.finished, !started);
          offset = piece.next;
          const spoken = speakable(piece.chunk);
          if (spoken) { if (!started) { beginSpeaking(); started = true; } enqueue(spoken); }
          if (reply.finished) { if (started) endSpeaking(); else resume(); return; }
        }
        if (started) endSpeaking(); else resume();
      } catch (error) { setNote(error.message); resume(); }
    }

    function resume() { if (!state.alive) return; vad.reset(); setCaption(''); setNote(''); set('listening', 'Listening…'); }

    function beginSpeaking() { vad.reset(); queue = []; streamDone = false; setCaption(''); set('speaking', 'Speaking · click the orb to interrupt'); }
    function enqueue(text) {
      if (state.mode !== 'speaking') return;
      for (const part of splitText(text, maxSpeechLength(settings.speaker))) queue.push(part);
      if (!draining) drain();
    }
    function endSpeaking() { streamDone = true; if (!draining && state.mode === 'speaking') resume(); }
    const cloudSpeaker = () => settings.speaker !== 'system' && (settings.speaker === 'nvidiaNIM' || settings.keys[settings.speaker]);
    // Start fetching audio for a piece right away, so the next sentence is ready when the current one ends.
    function fetchPiece(text) {
      if (!cloudSpeaker()) return { text, audio: null };
      const audio = result(bridge.voiceSpeak(text, settings.speaker)).then(encoded => Uint8Array.from(atob(encoded), c => c.charCodeAt(0)));
      audio.catch(() => {});
      return { text, audio };
    }
    async function drain() {
      draining = true;
      // Up to three pieces are fetched at once, in order, so the next sentence is ready before the current one ends.
      const pipeline = [];
      while (state.alive && state.mode === 'speaking') {
        while (pipeline.length < 3 && queue.length) pipeline.push(fetchPiece(queue.shift()));
        if (!pipeline.length) break;
        await speakPiece(pipeline.shift());
      }
      draining = false;
      if (state.alive && state.mode === 'speaking' && streamDone && !queue.length) resume();
    }
    async function speakPiece({ text, audio }) {
      if (!audio) { await speakSystem(text); return; }
      let bytes;
      try { bytes = await audio; }
      catch (error) { setNote(`${error.message} Using the Windows voice instead.`); await speakSystem(text); return; }
      if (state.mode === 'speaking') await playAudio(bytes);
    }

    const speechSpeed = () => Math.min(Math.max(Number(settings.speed) || 1, 0.75), 1.5);
    function speakSystem(text) {
      return new Promise(done => {
        const synth = window.speechSynthesis, voices = synth.getVoices();
        const language = (settings.language || navigator.language || 'en-US').slice(0, 2);
        const voice = voices.find(v => v.lang.startsWith(language) && /natural|online/i.test(v.name)) || voices.find(v => v.lang.startsWith(language));
        const parts = text.match(/[^.!?]+[.!?]*\s*/g) || [text];
        let finished = false; const finish = () => { if (!finished) { finished = true; state.cancelSpeech = null; done(); } };
        state.cancelSpeech = () => { synth.cancel(); finish(); };
        parts.forEach((part, index) => {
          const utterance = new SpeechSynthesisUtterance(part.trim()); if (voice) utterance.voice = voice; utterance.rate = speechSpeed();
          if (index === parts.length - 1) { utterance.onend = finish; utterance.onerror = finish; }
          synth.speak(utterance);
        });
      });
    }

    function playAudio(bytes) {
      return new Promise(done => {
        const url = URL.createObjectURL(new Blob([bytes], { type: bytes[0] === 0x52 && bytes[1] === 0x49 ? 'audio/wav' : 'audio/mpeg' }));
        const player = new Audio(url); player.playbackRate = speechSpeed();
        const finish = () => { URL.revokeObjectURL(url); state.cancelSpeech = null; done(); };
        state.cancelSpeech = () => { player.pause(); finish(); };
        player.onended = finish; player.onerror = finish;
        player.play().catch(finish);
      });
    }

    // Drag the card by its handle or the orb and waveform row; it remembers where you left it.
    let pos = { x: 0, y: 0 }, dragStart = null;
    try { const saved = JSON.parse(localStorage.getItem('voiceCardPos') || 'null'); if (saved && Number.isFinite(saved.x) && Number.isFinite(saved.y)) pos = saved; } catch {}
    const place = () => {
      const maxX = Math.max(0, (window.innerWidth - card.offsetWidth) / 2 - 8);
      pos = { x: Math.min(Math.max(pos.x, -maxX), maxX), y: Math.min(Math.max(pos.y, 0), Math.max(0, window.innerHeight - 56 - card.offsetHeight - 8)) };
      card.style.transform = `translate(${pos.x}px, ${pos.y}px)`;
    };
    for (const handle of [grip, top]) {
      handle.addEventListener('pointerdown', event => { if (event.target.closest('button')) return; dragStart = { x: event.clientX - pos.x, y: event.clientY - pos.y }; handle.setPointerCapture(event.pointerId); event.preventDefault(); });
      handle.addEventListener('pointermove', event => { if (!dragStart) return; pos = { x: event.clientX - dragStart.x, y: event.clientY - dragStart.y }; place(); });
      for (const name of ['pointerup', 'pointercancel']) handle.addEventListener(name, () => { if (!dragStart) return; dragStart = null; try { localStorage.setItem('voiceCardPos', JSON.stringify(pos)); } catch {} });
    }
    window.addEventListener('resize', place); place();
    orb.addEventListener('click', () => { if (state.mode === 'speaking') { queue = []; state.cancelSpeech?.(); resume(); } });
    end.addEventListener('click', stop);
    gear.addEventListener('click', () => { stop(); openSettings?.(); });
    chat.addEventListener('click', () => {
      const showing = chat.getAttribute('aria-pressed') !== 'true';
      chat.setAttribute('aria-pressed', String(showing)); chat.setAttribute('aria-label', showing ? 'Hide captions' : 'Show captions'); line.hidden = !showing;
    });
    mic.addEventListener('click', () => {
      state.muted = !state.muted; vad.reset();
      mic.setAttribute('aria-pressed', String(state.muted)); mic.setAttribute('aria-label', state.muted ? 'Unmute microphone' : 'Mute microphone');
      mic.innerHTML = state.muted ? ICONS.micOff : ICONS.mic; overlay.dataset.muted = String(state.muted); renderLine();
    });
    // The bars follow your voice while listening, ripple while the Bot speaks, and breathe while it thinks.
    const animate = time => {
      const t = time / 1000;
      bars.forEach((bar, index) => {
        const phase = index * 0.55, bump = 0.45 + 0.55 * Math.sin(Math.PI * index / (bars.length - 1)), ripple = Math.abs(Math.sin(t * 6 + phase));
        let height = 4;
        if (state.mode === 'listening') height = state.muted ? 4 : 4 + level * (0.35 + 0.65 * ripple) * 32;
        else if (state.mode === 'speaking') height = 4 + 0.55 * (0.4 + 0.6 * Math.abs(Math.sin(t * 5 + phase))) * bump * 32;
        else if (state.mode === 'thinking') height = 4 + (0.5 + 0.5 * Math.sin(t * 3 + phase)) * 6;
        bar.style.height = `${height}px`;
      });
      level *= 0.85;
      frame = requestAnimationFrame(animate);
    };
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) frame = requestAnimationFrame(animate);
    overlay.addEventListener('keydown', event => { if (event.key === 'Escape') stop(); });

    function stop() {
      if (!session) return;
      session = null; state.alive = false; queue = []; state.cancelSpeech?.(); cancelAnimationFrame(frame); window.removeEventListener('resize', place);
      window.speechSynthesis.cancel();
      processor.disconnect(); source.disconnect(); stream.getTracks().forEach(track => track.stop()); audio.close().catch(() => {});
      overlay.remove();
    }
  }

  function stop() { session?.stop(); }

  async function renderSettings(page) {
    if (!bridge.voiceSettings) { page.append(el('p', 'muted', 'Voice settings are available in the installed app.')); return; }
    const settings = await result(bridge.voiceSettings());
    const form = el('div', 'voice-settings');
    const row = (label, control) => { const wrap = el('label', 'voice-row'); wrap.append(el('span', '', label), control); return wrap; };
    const select = (options, value, change) => {
      const control = el('select'); for (const [id, title] of options) { const option = el('option', '', title); option.value = id; control.append(option); }
      control.value = value; control.addEventListener('change', () => change(control.value)); return control;
    };
    const save = patch => result(bridge.voiceSave(patch)).catch(error => toast(error.message));
    form.append(
      el('p', 'muted', 'Listening needs a cloud key because Windows has no offline recognizer here; Groq has a free tier. Speaking is free using Windows voices. Audio and reply text go only to the provider you choose. Keys are encrypted on this PC.'),
      row('Listening', select([['groq', 'Groq (Whisper)'], ['openAI', 'OpenAI (Whisper)'], ['elevenLabs', 'ElevenLabs (Scribe)']], settings.transcriber, value => save({ transcriber: value }))),
      row('Speaking', select([['system', 'Windows voice (free)'], ['groq', 'Groq (Orpheus)'], ['elevenLabs', 'ElevenLabs'], ['openAI', 'OpenAI'], ['gemini', 'Google AI Studio (Gemini)'], ['nvidiaCloud', 'NVIDIA Cloud (hosted Magpie)'], ['nvidiaNIM', 'NVIDIA NIM (Magpie, self-hosted)']], settings.speaker, value => save({ speaker: value }))),
    );
    const talk = el('input'); talk.type = 'checkbox'; talk.checked = settings.talkOver; talk.addEventListener('change', () => save({ talkOver: talk.checked }));
    form.append(row('Allow talking over replies', talk));
    const pace = el('input'); pace.type = 'range'; pace.min = '0.75'; pace.max = '1.5'; pace.step = '0.05'; pace.value = String(settings.speed || 1);
    pace.addEventListener('change', () => save({ speed: Number(pace.value) }));
    form.append(row('Speaking speed', pace));
    for (const [id, title] of [['groq', 'Groq'], ['openAI', 'OpenAI'], ['elevenLabs', 'ElevenLabs'], ['gemini', 'Google AI Studio'], ['nvidiaCloud', 'NVIDIA Cloud (nvapi- key)'], ['nvidiaNIM', 'NVIDIA NIM (only if your server needs one)']]) {
      const input = el('input'); input.type = 'password'; input.autocomplete = 'off'; input.placeholder = settings.keys[id] ? 'Saved — paste a new key to replace' : 'Paste API key';
      const keep = el('button', '', 'Save key'); keep.type = 'button';
      keep.addEventListener('click', async () => { try { await result(bridge.voiceKey(id, input.value.trim())); input.value = ''; input.placeholder = 'Saved — paste a new key to replace'; toast(`${title} key saved.`); } catch (error) { toast(error.message); } });
      const clear = el('button', '', 'Remove'); clear.type = 'button';
      clear.addEventListener('click', async () => { try { await result(bridge.voiceKey(id, '')); input.placeholder = 'Paste API key'; toast(`${title} key removed.`); } catch (error) { toast(error.message); } });
      const line = el('div', 'voice-key'); line.append(input, keep, clear); form.append(row(`${title} key`, line));
    }
    const voiceID = el('input'); voiceID.value = settings.voiceID; voiceID.addEventListener('change', () => save({ voiceID: voiceID.value.trim() }));
    form.append(row('ElevenLabs voice ID', voiceID));
    form.append(row('Groq voice', select(['autumn', 'diana', 'hannah', 'austin', 'daniel', 'troy'].map(name => [name, name[0].toUpperCase() + name.slice(1)]), settings.groqVoice || 'autumn', value => save({ groqVoice: value }))));
    const nimURL = el('input'); nimURL.value = settings.nimURL || 'http://localhost:9000'; nimURL.addEventListener('change', () => save({ nimURL: nimURL.value.trim() }));
    const nimVoice = el('input'); nimVoice.value = settings.nimVoice || 'Magpie-Multilingual.EN-US.Aria'; nimVoice.addEventListener('change', () => save({ nimVoice: nimVoice.value.trim() }));
    const text = (value, fallback, key) => { const input = el('input'); input.value = value || fallback; input.addEventListener('change', () => save({ [key]: input.value.trim() })); return input; };
    form.append(
      row('Gemini model', text(settings.geminiModel, 'gemini-2.5-flash-preview-tts', 'geminiModel')),
      row('Gemini voice', select(['Kore', 'Puck', 'Zephyr', 'Charon', 'Fenrir', 'Aoede', 'Leda', 'Orus', 'Callirrhoe', 'Enceladus'].map(name => [name, name]), settings.geminiVoice || 'Kore', value => save({ geminiVoice: value }))),
      row('Gemini base URL', text(settings.geminiBase, 'https://generativelanguage.googleapis.com', 'geminiBase')),
      el('p', 'muted', 'Google AI Studio speaking uses a key from aistudio.google.com. Google changes its speech model names often: if speech fails, check the current speech model name in AI Studio.'),
      row('NVIDIA Cloud server', text(settings.nvcServer, 'grpc.nvcf.nvidia.com:443', 'nvcServer')),
      row('NVIDIA Cloud function (model) ID', text(settings.nvcFunction, '877104f7-e885-42b9-8de8-f6e4c6303969', 'nvcFunction')),
      row('NVIDIA Cloud voice', text(settings.nvcVoice, 'Magpie-Multilingual.EN-US.Aria', 'nvcVoice')),
      el('p', 'muted', 'NVIDIA Cloud speaking uses your NVIDIA API key (starts with nvapi-) and the function ID from the model’s page on build.nvidia.com. It uses NVIDIA’s gRPC speech service and has not been tested against it; if it fails the Windows voice is used and the reason is shown.'));
    form.append(row('NVIDIA NIM address', nimURL), row('NVIDIA NIM voice', nimVoice),
      el('p', 'muted', 'NVIDIA NIM speaks with a Magpie TTS NIM you run yourself (a Docker container on an NVIDIA GPU, usually at port 9000). NVIDIA’s hosted cloud endpoint uses gRPC and is not supported here. Groq and ElevenLabs voices are usually the quickest to start speaking.'));
    page.append(form);
  }

  return { start, stop, renderSettings, get active() { return !!session; } };
}
