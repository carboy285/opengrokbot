import { Vad, encodeWav, maxSpeechLength, nextChunk, rms, speakable, splitText, silenceFor, continuesThought, resample16k, acknowledgement, stepPhrase } from './voice-core.mjs';

// Hands-free voice mode for Windows.
// 0.9.3: listening and speaking can run on this PC with open-source models (Whisper and Kokoro), with no key.
// Voice mode keeps running when you open another Bot, and shows as a card, full screen, or a small pill.

const el = (tag, className = '', text = '') => { const node = document.createElement(tag); if (className) node.className = className; if (text) node.textContent = text; return node; };
const toBase64 = bytes => { let binary = ''; for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(binary); };

const icon = body => `<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
const ICONS = {
  gear: icon('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
  chat: icon('<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>'),
  mic: icon('<path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/>'),
  micOff: icon('<line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.1 2.1M15 9.3V4a3 3 0 0 0-5.9-.8"/><path d="M19 10v2a7 7 0 0 1-.1 1.2M5 10v2a7 7 0 0 0 11.7 5.2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/>'),
  close: icon('<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>'),
  expand: icon('<polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/><line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/>'),
  shrink: icon('<polyline points="4 14 10 14 10 20"/><polyline points="20 10 14 10 14 4"/><line x1="14" y1="10" x2="21" y2="3"/><line x1="3" y1="21" x2="10" y2="14"/>'),
  minimize: icon('<line x1="5" y1="12" x2="19" y2="12"/>')
};
const toB64Float = samples => toBase64(new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength));

export function createVoice({ bridge, result, toast, currentBot, latestReply, activitySince, sendText, openSettings, avatar, openBot }) {
  let session = null;

  async function start() {
    const bot = currentBot();
    if (!bot) return;
    if (session) {
      // Voice is already on for a Bot: bring it back, or move it to this Bot.
      if (session.botID === bot.id) { session.setLayout(session.preferred); return; }
      session.stop();
    }
    const settings = await result(bridge.voiceSettings());
    // This Bot's own voice choices win over the app-wide ones. 'apple' is the built-in voice (the Windows voice here).
    const own = bot.voice || {};
    if (own.speaker) settings.speaker = own.speaker === 'apple' ? 'system' : own.speaker;
    if (own.speed) settings.speed = own.speed;
    settings.language = own.language && own.language !== 'auto' ? own.language : (navigator.language || 'en-US');
    const localListening = settings.transcriber === 'local', localSpeaking = settings.speaker === 'local';
    if (!localListening && !settings.keys[settings.transcriber]) {
      toast('Voice needs a way to listen. Choose “On this PC (free)” or add a Groq key in Settings → Voice.');
      openSettings?.(); return;
    }
    let stream;
    try { stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } }); }
    catch { toast('The microphone is blocked. Allow microphone access in Windows privacy settings.'); return; }

    // ---- Layout: one overlay that is a card, full screen, or a small pill ----
    const overlay = el('div', 'voice-overlay'); overlay.setAttribute('role', 'dialog'); overlay.setAttribute('aria-label', `Voice mode with ${bot.name}`);
    const card = el('div', 'voice-card');
    const header = el('div', 'voice-head');
    const who = el('button', 'voice-who'); who.type = 'button'; who.title = `Open ${bot.name}`;
    const face = avatar ? avatar(bot) : el('span'); face.classList.add('voice-face');
    who.append(face, el('span', 'voice-name', bot.name));
    const status = el('span', 'voice-status', 'Listening…'); who.append(status);
    const control = (className, body, label) => { const node = el('button', className); node.type = 'button'; node.innerHTML = body; node.setAttribute('aria-label', label); node.title = label; return node; };
    const size = control('voice-size', ICONS.expand, 'Full screen');
    const mini = control('voice-min', ICONS.minimize, 'Minimize');
    header.append(who, size, mini);
    const top = el('div', 'voice-top');
    const orb = el('button', 'voice-orb'); orb.type = 'button'; orb.setAttribute('aria-label', 'Hold to keep talking. Click to interrupt.'); orb.append(el('span'), el('span'));
    const wave = el('div', 'voice-wave'); wave.setAttribute('aria-hidden', 'true');
    const bars = Array.from({ length: 32 }, () => { const bar = document.createElement('i'); wave.append(bar); return bar; });
    top.append(orb, wave);
    const captions = el('div', 'voice-captions'); captions.setAttribute('aria-live', 'polite');
    const youLine = el('p', 'voice-you'), botLine = el('p', 'voice-bot'), line = el('div', 'voice-line');
    captions.append(youLine, botLine, line);
    const controls = el('div', 'voice-controls');
    const gear = control('voice-gear', ICONS.gear, 'Voice settings');
    const chat = control('voice-chat', ICONS.chat, 'Hide captions'); chat.setAttribute('aria-pressed', 'true');
    const mic = control('voice-mic', ICONS.mic, 'Mute microphone'); mic.setAttribute('aria-pressed', 'false');
    const end = control('voice-end', ICONS.close, 'End voice mode');
    const hint = el('span', 'voice-hint', 'Hold Space or the orb to keep talking');
    controls.append(gear, chat, hint, mic, end);
    const grip = el('div', 'voice-grip'); grip.setAttribute('aria-label', 'Drag to move the voice card'); grip.append(el('span'));
    card.append(grip, header, top, captions, controls);
    const pill = el('div', 'voice-pill');
    const pillWho = el('button', 'voice-pill-who'); pillWho.type = 'button';
    const pillFace = avatar ? avatar(bot) : el('span'); pillFace.classList.add('voice-face');
    const pillWave = el('span', 'voice-pill-wave'); for (let i = 0; i < 5; i++) pillWave.append(el('i'));
    const pillStatus = el('span', 'voice-pill-status', 'Listening');
    pillWho.append(pillFace, el('strong', '', bot.name), pillWave, pillStatus);
    const pillOpen = control('voice-pill-open', ICONS.expand, 'Expand voice mode'), pillEnd = control('voice-pill-end', ICONS.close, 'End voice mode');
    pill.append(pillWho, pillOpen, pillEnd);
    overlay.append(card, pill);
    document.body.append(overlay);

    let layout = 'card', preferred = settings.layout === 'full' ? 'full' : 'card';
    let pos = { x: 0, y: 0 }, dragStart = null;
    try { const saved = JSON.parse(localStorage.getItem('voiceCardPos') || 'null'); if (saved && Number.isFinite(saved.x) && Number.isFinite(saved.y)) pos = saved; } catch {}

    function setLayout(next) {
      layout = next; if (next !== 'mini') preferred = next;
      overlay.dataset.layout = next;
      size.innerHTML = next === 'full' ? ICONS.shrink : ICONS.expand; size.setAttribute('aria-label', next === 'full' ? 'Small card' : 'Full screen'); size.title = size.getAttribute('aria-label');
      if (next !== 'mini') place();
      document.body.classList.toggle('voice-full', next === 'full');
    }
    size.addEventListener('click', () => { const next = layout === 'full' ? 'card' : 'full'; setLayout(next); result(bridge.voiceSave({ layout: next })).catch(() => {}); });
    mini.addEventListener('click', () => setLayout('mini'));
    pillOpen.addEventListener('click', () => setLayout(preferred));
    for (const target of [who, pillWho]) target.addEventListener('click', () => openBot?.(bot.id));

    let statusText = 'Listening…', noteText = '', level = 0, frame = 0;
    const renderLine = () => {
      const text = noteText || (state.muted ? 'Muted' : statusText);
      line.textContent = text; status.textContent = state.muted ? 'Muted' : statusText.replace('…', '');
      pillStatus.textContent = state.muted ? 'Muted' : ({ listening: 'Listening', thinking: 'Thinking', speaking: 'Speaking' })[state.mode] || '';
    };
    const setNote = text => { noteText = text; renderLine(); };
    const setYou = text => { youLine.textContent = text; youLine.hidden = !text; };
    const setBot = text => { botLine.textContent = text; botLine.hidden = !text; };
    setYou(''); setBot('');

    const audio = new AudioContext();
    const source = audio.createMediaStreamSource(stream);
    const processor = audio.createScriptProcessor(2048, 1, 1);
    const vad = new Vad({ sampleRate: audio.sampleRate, silenceMs: silenceFor(settings.patience) });
    const state = { mode: 'listening', alive: true, cancelSpeech: null, muted: false, holding: false, preparing: false };
    let queue = [], draining = false, streamDone = false, pendingText = '', pendingTimer = null, turn = 0;
    session = { stop, botID: bot.id, setLayout, get preferred() { return preferred; } };
    bridge.voiceMode?.(bot.id, true).catch?.(() => {});

    const set = (mode, text) => { state.mode = mode; statusText = text; overlay.dataset.mode = mode; renderLine(); };
    set('listening', 'Listening…');
    setLayout(preferred);

    // Download or load the open-source models first if this setup uses them.
    if (localListening || localSpeaking) {
      state.preparing = true; set('thinking', 'Getting the voice ready…');
      const stopProgress = bridge.onLocalVoiceProgress?.(value => { if (value.total > 0) setNote(`Downloading the ${value.kind === 'stt' ? 'listening' : 'speaking'} model… ${Math.round(100 * value.loaded / value.total)}%`); });
      try { await result(bridge.localVoicePrepare(localListening && localSpeaking ? 'both' : localListening ? 'stt' : 'tts')); }
      catch (error) { setNote(`${error.message} Open Settings → Voice to choose another option.`); }
      finally { stopProgress?.(); state.preparing = false; }
      if (!state.alive) return;
      setNote(''); set('listening', 'Listening…');
    }

    processor.onaudioprocess = event => {
      if (!state.alive || state.preparing || state.mode === 'thinking' && !state.holding || state.muted) return;
      const chunk = new Float32Array(event.inputBuffer.getChannelData(0));
      level = Math.max(level, Math.min(1, rms(chunk) * 8));
      orb.style.setProperty('--level', String(level));
      const heard = vad.push(chunk, state.mode === 'speaking' ? 'speaking' : 'listening');
      if (!heard) return;
      if (heard.type === 'barge') { if (settings.talkOver) { queue = []; state.cancelSpeech?.(); set('listening', 'Listening…'); } else vad.reset(); return; }
      handleUtterance(heard.samples);
    };
    source.connect(processor); processor.connect(audio.destination);

    // Hold to keep talking: the app waits however long you pause, and sends when you let go.
    function hold(on) {
      if (!state.alive || state.muted) return;
      if (on) {
        if (state.holding) return;
        state.holding = true; vad.silenceMs = 1e9; overlay.dataset.holding = 'true';
        if (state.mode === 'speaking') { queue = []; state.cancelSpeech?.(); }
        if (state.mode !== 'listening') set('listening', 'Listening…');
        statusText = 'Listening — let go to send'; renderLine(); return;
      }
      if (!state.holding) return;
      state.holding = false; vad.silenceMs = silenceFor(settings.patience); delete overlay.dataset.holding;
      const heard = vad.finish();
      if (heard) handleUtterance(heard.samples, true); else set('listening', 'Listening…');
    }
    orb.addEventListener('pointerdown', event => { orb.setPointerCapture(event.pointerId); orb.dataset.pressed = String(Date.now()); hold(true); });
    for (const name of ['pointerup', 'pointercancel']) orb.addEventListener(name, () => {
      const pressed = Number(orb.dataset.pressed || 0); delete orb.dataset.pressed;
      hold(false);
      // A quick click while the Bot speaks interrupts it.
      if (Date.now() - pressed < 250 && state.mode === 'speaking') { queue = []; state.cancelSpeech?.(); resume(); }
    });
    const typing = target => target && (target.closest?.('input, textarea, select, [contenteditable="true"]'));
    const keyDown = event => { if (event.code === 'Space' && !event.repeat && !typing(event.target) && layout !== 'mini') { event.preventDefault(); hold(true); } };
    const keyUp = event => { if (event.code === 'Space' && state.holding) { event.preventDefault(); hold(false); } };
    window.addEventListener('keydown', keyDown); window.addEventListener('keyup', keyUp);

    async function transcribe(samples) {
      if (localListening) return result(bridge.localVoiceTranscribe(toB64Float(resample16k(samples, audio.sampleRate)), settings.language));
      return result(bridge.voiceTranscribe(toBase64(encodeWav(samples, audio.sampleRate))));
    }

    async function handleUtterance(samples, held = false) {
      const mine = ++turn;
      clearTimeout(pendingTimer);
      set('thinking', 'Transcribing…');
      let text;
      try { text = (await transcribe(samples))?.trim(); }
      catch (error) { setNote(error.message); resume(); return; }
      if (!state.alive || mine !== turn) return;
      if (!text) { if (pendingText) { send(pendingText); } else resume(); return; }
      const said = pendingText ? `${pendingText} ${text}` : text;
      // Sounds unfinished ("and…", "um", a comma): keep listening a little longer before sending.
      if (!held && continuesThought(said)) {
        pendingText = said; setYou(said); set('listening', 'Go on…');
        pendingTimer = setTimeout(() => { if (state.alive && pendingText && !vad.speaking && state.mode === 'listening') send(pendingText); }, Math.max(1400, silenceFor(settings.patience) * 1.8));
        return;
      }
      send(said);
    }

    async function send(text) {
      const mine = ++turn;
      clearTimeout(pendingTimer); pendingText = '';
      setYou(text); setBot(''); set('thinking', 'Thinking…');
      const before = latestReply(bot)?.id, sentAt = Date.now();
      try { await sendText(bot, text); }
      catch (error) { setNote(error.message); resume(); return; }
      // Speak finished sentences while the reply is still being written. Before it starts, say a short "one sec"
      // and what the Bot is doing (reading a page, asking another Bot) so the silence never feels dead.
      let offset = 0, speaking = false, replyStarted = false, acknowledged = false, lastStep = 0;
      const seenSteps = new Set();
      const say = text => { if (!speaking) { beginSpeaking(); speaking = true; } enqueue(text); };
      for (let waited = 0; state.alive && mine === turn && waited < 180000; waited += 40) {
        await new Promise(done => setTimeout(done, 40));
        if (speaking && state.mode !== 'speaking') { const reply = latestReply(bot); if (reply && reply.id !== before && !reply.finished) bridge.stop?.(bot.id); return; }
        const reply = latestReply(bot);
        const fresh = reply && reply.id !== before ? reply : null;
        if (!replyStarted && !(fresh && fresh.text)) {
          if (settings.narrate !== false && activitySince) for (const step of activitySince(bot, sentAt)) {
            if (seenSteps.has(step.id)) continue; seenSteps.add(step.id);
            const phrase = stepPhrase(step.text);
            if (phrase && Date.now() - lastStep > 3500) { lastStep = Date.now(); say(phrase); statusText = phrase.replace(/\.$/, '…'); renderLine(); }
          }
          if (settings.acknowledge !== false && !acknowledged && Date.now() - sentAt > 1300) { acknowledged = true; if (!speaking) say(acknowledgement()); }
          if (!fresh) continue;
        }
        if (!fresh) continue;
        const piece = nextChunk(fresh.text, offset, fresh.finished, !replyStarted);
        offset = piece.next;
        const spoken = speakable(piece.chunk);
        if (spoken) { replyStarted = true; say(spoken); setBot(speakable(fresh.text).slice(-400)); }
        if (fresh.finished) { if (speaking) endSpeaking(); else resume(); return; }
      }
      if (state.alive && mine === turn) { if (speaking) endSpeaking(); else resume(); }
    }

    function resume() { if (!state.alive) return; vad.reset(); setNote(''); set('listening', 'Listening…'); }

    function beginSpeaking() { vad.reset(); queue = []; streamDone = false; set('speaking', 'Speaking'); }
    function enqueue(text) {
      if (state.mode !== 'speaking') return;
      for (const part of splitText(text, localSpeaking ? 400 : maxSpeechLength(settings.speaker))) queue.push(part);
      if (!draining) drain();
    }
    function endSpeaking() { streamDone = true; if (!draining && state.mode === 'speaking') resume(); }
    const cloudSpeaker = () => settings.speaker !== 'system' && settings.speaker !== 'local' && (settings.speaker === 'nvidiaNIM' || settings.keys[settings.speaker]);
    // Start fetching audio for a piece right away, so the next sentence is ready when the current one ends.
    function fetchPiece(text) {
      let audio = null;
      if (localSpeaking) audio = result(bridge.localVoiceSpeak(text, own.kokoroVoice || settings.kokoroVoice, 1));
      else if (cloudSpeaker()) audio = result(bridge.voiceSpeak(text, settings.speaker));
      if (!audio) return { text, audio: null };
      audio = audio.then(encoded => Uint8Array.from(atob(encoded), c => c.charCodeAt(0)));
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
      if (state.alive && state.mode === 'speaking') { if (streamDone && !queue.length) resume(); else { statusText = 'Thinking…'; renderLine(); } }
    }
    async function speakPiece({ text, audio }) {
      if (state.mode === 'speaking') { statusText = 'Speaking'; renderLine(); }
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

    // Drag the card by its handle; it remembers where you left it. Full screen and the pill have fixed places.
    function place() {
      if (layout !== 'card') { card.style.transform = ''; return; }
      const maxX = Math.max(0, (window.innerWidth - card.offsetWidth) / 2 - 8);
      pos = { x: Math.min(Math.max(pos.x, -maxX), maxX), y: Math.min(Math.max(pos.y, 0), Math.max(0, window.innerHeight - 56 - card.offsetHeight - 8)) };
      card.style.transform = `translate(${pos.x}px, ${pos.y}px)`;
    }
    for (const handle of [grip, header]) {
      handle.addEventListener('pointerdown', event => { if (layout !== 'card' || event.target.closest('button')) return; dragStart = { x: event.clientX - pos.x, y: event.clientY - pos.y }; handle.setPointerCapture(event.pointerId); event.preventDefault(); });
      handle.addEventListener('pointermove', event => { if (!dragStart) return; pos = { x: event.clientX - dragStart.x, y: event.clientY - dragStart.y }; place(); });
      for (const name of ['pointerup', 'pointercancel']) handle.addEventListener(name, () => { if (!dragStart) return; dragStart = null; try { localStorage.setItem('voiceCardPos', JSON.stringify(pos)); } catch {} });
    }
    window.addEventListener('resize', place); place();
    end.addEventListener('click', stop); pillEnd.addEventListener('click', stop);
    gear.addEventListener('click', () => { setLayout('mini'); openSettings?.(); });
    chat.addEventListener('click', () => {
      const showing = chat.getAttribute('aria-pressed') !== 'true';
      chat.setAttribute('aria-pressed', String(showing)); chat.setAttribute('aria-label', showing ? 'Hide captions' : 'Show captions'); captions.hidden = !showing;
    });
    mic.addEventListener('click', () => {
      state.muted = !state.muted; vad.reset();
      mic.setAttribute('aria-pressed', String(state.muted)); mic.setAttribute('aria-label', state.muted ? 'Unmute microphone' : 'Mute microphone');
      mic.innerHTML = state.muted ? ICONS.micOff : ICONS.mic; overlay.dataset.muted = String(state.muted); renderLine();
    });
    // The bars follow your voice while listening, ripple while the Bot speaks, and breathe while it thinks.
    const pillBars = [...pillWave.children];
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
      pillBars.forEach((bar, index) => { const amount = state.mode === 'listening' ? level : state.mode === 'speaking' ? 0.5 + 0.5 * Math.abs(Math.sin(t * 6 + index)) : 0.15; bar.style.transform = `scaleY(${0.25 + amount * 0.75})`; });
      orb.style.setProperty('--pulse', String(state.mode === 'speaking' ? 0.5 + 0.5 * Math.abs(Math.sin(t * 4)) : state.mode === 'thinking' ? 0.2 + 0.2 * Math.sin(t * 2) : level));
      level *= 0.85;
      frame = requestAnimationFrame(animate);
    };
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) frame = requestAnimationFrame(animate);
    overlay.addEventListener('keydown', event => { if (event.key === 'Escape') { event.stopPropagation(); setLayout(layout === 'full' ? 'card' : 'mini'); } });

    function stop() {
      if (!session || !state.alive) return;
      session = null; state.alive = false; queue = []; state.cancelSpeech?.(); cancelAnimationFrame(frame); clearTimeout(pendingTimer);
      window.removeEventListener('resize', place); window.removeEventListener('keydown', keyDown); window.removeEventListener('keyup', keyUp);
      window.speechSynthesis.cancel(); document.body.classList.remove('voice-full');
      bridge.voiceMode?.(bot.id, false).catch?.(() => {});
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
      el('p', 'muted', 'Voice can run entirely on this PC with free open-source models: Whisper listens and Kokoro speaks. Nothing leaves the PC. Cloud providers are optional; audio and reply text go only to the provider you choose, and keys are encrypted on this PC.'),
      row('Listening', select([['local', 'On this PC — Whisper (free, private)'], ['groq', 'Groq (Whisper)'], ['openAI', 'OpenAI (Whisper)'], ['elevenLabs', 'ElevenLabs (Scribe)']], settings.transcriber, value => save({ transcriber: value }))),
      row('Speaking', select([['local', 'On this PC — Kokoro (free, natural)'], ['system', 'Windows voice (free)'], ['groq', 'Groq (Orpheus)'], ['elevenLabs', 'ElevenLabs'], ['openAI', 'OpenAI'], ['gemini', 'Google AI Studio (Gemini)'], ['nvidiaCloud', 'NVIDIA Cloud (hosted Magpie)'], ['nvidiaNIM', 'NVIDIA NIM (Magpie, self-hosted)']], settings.speaker, value => save({ speaker: value }))),
    );
    // ---- Open-source models on this PC ----
    const local = el('div', 'settings-card local-voice-card');
    form.append(el('h3', '', 'Open-source voice on this PC'), local);
    const drawLocal = async () => {
      local.replaceChildren(el('p', 'muted', 'Checking this PC…'));
      let info;
      try { info = await result(bridge.localVoiceStatus()); } catch (error) { local.replaceChildren(el('p', 'muted', error.message)); return; }
      const r = info.recommended, have = new Set(info.installed.models);
      const ready = info.installed.runtime && have.has('onnx-community/Kokoro-82M-v1.0-ONNX') && have.has(info.stt.model);
      local.replaceChildren(
        el('p', 'local-badge', `Recommended for this PC · ${r.tier}`),
        el('p', '', r.why),
        el('p', 'muted', `${info.memoryGB} GB memory · ${info.cores} cores · ${info.webgpu ? 'graphics chip available' : 'processor only'}`),
        el('p', '', `Speaking: ${r.speaker}`), el('p', '', `Listening: ${r.listener}`),
        el('p', 'muted', ready ? 'Downloaded and ready. It works offline.' : `About ${r.downloadMB} MB, downloaded once.`));
      const progress = el('p', 'muted'); const stopProgress = bridge.onLocalVoiceProgress?.(value => { if (value.total) progress.textContent = `Downloading ${value.kind === 'stt' ? 'Whisper' : 'Kokoro'}… ${Math.round(100 * value.loaded / value.total)}%`; });
      const download = el('button', 'pill primary', ready ? 'Check models' : `Download recommended (${r.downloadMB} MB)`); download.type = 'button';
      download.addEventListener('click', async () => {
        download.disabled = true; progress.textContent = 'Starting download…';
        try { await result(bridge.localVoiceChoose('recommended')); await result(bridge.localVoicePrepare('both')); await save({ transcriber: 'local', speaker: 'local' }); toast('The open-source voice is ready.'); stopProgress?.(); drawLocal(); }
        catch (error) { progress.textContent = error.message; download.disabled = false; }
      });
      const whisper = select([['onnx-community/whisper-tiny.en', 'Whisper tiny · English · fastest'], ['onnx-community/whisper-base.en', 'Whisper base · English'], ['onnx-community/whisper-small.en', 'Whisper small · English · most accurate'], ['onnx-community/whisper-tiny', 'Whisper tiny · any language'], ['onnx-community/whisper-base', 'Whisper base · any language'], ['onnx-community/whisper-small', 'Whisper small · any language']], info.stt.model, value => result(bridge.localVoiceChoose({ stt: { model: value } })).then(drawLocal).catch(error => toast(error.message)));
      const kokoro = select([['q8', 'Kokoro · small and quick (92 MB)'], ['fp16', 'Kokoro · balanced (163 MB)'], ['fp32', 'Kokoro · full quality (326 MB)']], info.tts.dtype, value => result(bridge.localVoiceChoose({ tts: { dtype: value } })).then(drawLocal).catch(error => toast(error.message)));
      const device = select([['wasm', 'Processor'], ...(info.webgpu ? [['webgpu', 'Graphics chip (faster)']] : [])], info.tts.device, value => result(bridge.localVoiceChoose({ tts: { device: value }, stt: { device: value } })).then(drawLocal).catch(error => toast(error.message)));
      const voiceSelect = select(info.voices, settings.kokoroVoice || 'af_heart', value => { settings.kokoroVoice = value; save({ kokoroVoice: value }); });
      const preview = el('button', 'pill', 'Preview'); preview.type = 'button';
      preview.addEventListener('click', async () => {
        preview.disabled = true;
        try { const encoded = await result(bridge.localVoiceSpeak('Hi! This is how I sound when I talk to you.', voiceSelect.value, 1)); const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0)); const url = URL.createObjectURL(new Blob([bytes], { type: 'audio/wav' })); const player = new Audio(url); player.onended = () => URL.revokeObjectURL(url); await player.play(); }
        catch (error) { toast(error.message); } finally { preview.disabled = false; }
      });
      const remove = el('button', 'pill', 'Remove downloaded models'); remove.type = 'button';
      remove.addEventListener('click', async () => { try { await result(bridge.localVoiceRemove()); toast('Voice models removed.'); drawLocal(); } catch (error) { toast(error.message); } });
      // Measure here: below 0.5× real time feels instant. The graphics chip is kept only if it is clearly faster.
      const speed = el('p', 'muted');
      const pace = value => value == null ? 'not tested' : `${value.toFixed(2)}× real time${value < 0.5 ? ' (instant)' : value < 1 ? ' (good)' : ' (slow: try a smaller model)'}`;
      const describe = r => `Speaking: ${pace(r.tts?.realTimeFactor)} on the ${r.device === 'webgpu' ? 'graphics chip' : 'processor'} · ${r.threads} core${r.threads === 1 ? '' : 's'}` + (r.stt ? ` · Listening: ${pace(r.stt.realTimeFactor)} · heard “${r.stt.heard}”` : '');
      const measure = compare => async () => {
        speed.textContent = compare ? 'Comparing the processor and the graphics chip…' : 'Testing…';
        try { speed.textContent = describe(await result(bridge.localVoiceBenchmark(settings.transcriber === 'local', compare))); if (compare) drawLocal(); }
        catch (error) { speed.textContent = error.message; }
      };
      const testSpeed = el('button', 'pill', 'Test speed'); testSpeed.type = 'button'; testSpeed.addEventListener('click', measure(false));
      const tryGPU = el('button', 'pill', 'Use the graphics chip if it’s faster'); tryGPU.type = 'button'; tryGPU.addEventListener('click', measure(true));
      if (!ready) { testSpeed.disabled = true; tryGPU.disabled = true; }
      local.append(append2(el('div', 'row-actions'), download), progress, append2(el('div', 'row-actions'), testSpeed, tryGPU), speed,
        row('Kokoro voice', append2(el('div', 'voice-key'), voiceSelect, preview)),
        row('Listening model', whisper), row('Speaking model', kokoro), row('Run on', device), append2(el('div', 'row-actions'), remove));
    };
    const append2 = (parent, ...children) => { parent.append(...children); return parent; };
    drawLocal();

    // ---- Conversation feel ----
    form.append(el('h3', '', 'Conversation'));
    form.append(row('Wait before sending', select([['quick', 'Quick — answers fast'], ['normal', 'Normal'], ['relaxed', 'Relaxed — lots of time to think']], settings.patience || 'normal', value => save({ patience: value }))));
    form.append(el('p', 'muted', 'Voice mode waits longer when you trail off (“and…”, “um”). Hold Space or the orb to keep talking as long as you like; it sends when you let go.'));
    const ack = el('input'); ack.type = 'checkbox'; ack.checked = settings.acknowledge !== false; ack.addEventListener('change', () => save({ acknowledge: ack.checked }));
    form.append(row('Say “one sec” while thinking', ack));
    const narrate = el('input'); narrate.type = 'checkbox'; narrate.checked = settings.narrate !== false; narrate.addEventListener('change', () => save({ narrate: narrate.checked }));
    form.append(row('Say what the Bot is doing', narrate));
    form.append(row('Opens as', select([['card', 'Small card'], ['full', 'Full screen']], settings.layout || 'card', value => save({ layout: value }))));

    // ---- Speed ----
    form.append(el('h3', '', 'Faster answers'));
    const fast = el('input'); fast.type = 'checkbox'; fast.checked = settings.fastModel !== false; fast.addEventListener('change', () => save({ fastModel: fast.checked }));
    form.append(row('Use a quick model in voice mode', fast));
    form.append(el('p', 'muted', 'In voice mode Bots answer in a short, spoken style. With this on, Claude Code uses Haiku, Gemini CLI uses Gemini Flash and Codex thinks less (low reasoning effort). Ollama and LM Studio run on this PC and are already quick. Leave a box empty for the default.'));
    const models = { ...(settings.voiceModels || {}) };
    for (const [id, title, placeholder] of [['claude', 'Claude Code', 'haiku'], ['codex', 'Codex', 'same as chat, low effort'], ['gemini', 'Gemini CLI', 'gemini-2.5-flash'], ['grok', 'Grok Build', 'same as chat'], ['opencode', 'OpenCode', 'same as chat'], ['ollama', 'Ollama', 'same as chat'], ['lmstudio', 'LM Studio', 'same as chat']]) {
      const input = el('input'); input.value = models[id] || ''; input.placeholder = placeholder;
      input.addEventListener('change', () => { models[id] = input.value.trim(); save({ voiceModels: models }); });
      form.append(row(`${title} voice model`, input));
    }

    form.append(el('h3', '', 'More'));
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

  return { start, stop, renderSettings, get active() { return !!session; }, get botID() { return session?.botID || null; } };
}
