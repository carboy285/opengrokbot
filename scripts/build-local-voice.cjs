#!/usr/bin/env node
// Bundles local-voice/engine.mjs (Kokoro + Whisper through Transformers.js) into one browser script used by
// the Windows app (desktop-windows/renderer/local-voice-engine.js) and the Mac app (GrokBotMac/Resources/local-voice-engine.js).
// Build once after: npm install --no-save kokoro-js@1.2.1 @huggingface/transformers@3.7.6 esbuild@0.25.10 (kept out of package.json so
// installers and CI do not pull the 500 MB native runtime). The bundle is committed.
// The onnxruntime WebAssembly files are not bundled: the apps download them once and check their SHA-256 (see LOCAL_VOICE_RUNTIME).
const path = require('node:path'), fs = require('node:fs');
const root = path.resolve(__dirname, '..');
const outputs = ['desktop-windows/renderer/local-voice-engine.js', 'GrokBotMac/Resources/local-voice-engine.js'];
require('esbuild').build({
  entryPoints: [path.join(root, 'local-voice/engine.mjs')], bundle: true, format: 'iife', platform: 'browser', target: ['chrome120', 'safari17'],
  minify: true, legalComments: 'eof', outfile: path.join(root, outputs[0]), logLevel: 'warning',
  // Node-only modules Transformers.js and kokoro-js use outside a browser become empty modules here.
  plugins: [{ name: 'node-only-empty', setup(build) {
    build.onResolve({ filter: /^(fs|path|url|sharp|onnxruntime-node|fs\/promises|node:.*)$/ }, args => ({ path: args.path, namespace: 'empty' }));
    build.onLoad({ filter: /.*/, namespace: 'empty' }, () => ({ contents: 'export default {};', loader: 'js' }));
  } }],
  define: { 'process.env.NODE_ENV': '"production"' }
}).then(() => {
  for (const other of outputs.slice(1)) fs.copyFileSync(path.join(root, outputs[0]), path.join(root, other));
  console.log('Built', outputs.join(', '), (fs.statSync(path.join(root, outputs[0])).size / 1e6).toFixed(1) + ' MB');
}).catch(error => { console.error(error); process.exit(1); });
