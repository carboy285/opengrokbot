'use strict';
// Canvas: saves what the human edited in the Canvas panel into the Bot's own working folder.
// The file name is cleaned, the file always lands directly inside the folder (never outside it) and never replaces an existing file.
const fs = require('node:fs/promises');
const path = require('node:path');

const MAX_BYTES = 1_000_000;
const EXTENSIONS = { javascript: 'js', js: 'js', typescript: 'ts', ts: 'ts', python: 'py', py: 'py', html: 'html', css: 'css', json: 'json', markdown: 'md', md: 'md', bash: 'sh', sh: 'sh', shell: 'sh', swift: 'swift', rust: 'rs', go: 'go', java: 'java', c: 'c', cpp: 'cpp', sql: 'sql', yaml: 'yml', yml: 'yml', xml: 'xml', text: 'txt', txt: 'txt' };
const BLOCKED = new Set(['exe', 'dll', 'bat', 'cmd', 'com', 'scr', 'msi', 'lnk', 'ps1', 'vbs', 'app', 'dmg', 'jar', 'reg']);

/** A plain file name with an extension, or null if nothing usable is left. Directory parts, dots and control characters are removed. */
function safeName(name, language = '') {
  let base = path.basename(String(name ?? '').replace(/\\/g, '/')).replace(/[\u0000-\u001f<>:"|?*]/g, '').replace(/^\.+/, '').replace(/\s+/g, ' ').trim().slice(0, 80);
  if (!base) base = 'canvas';
  let ext = path.extname(base).slice(1).toLowerCase();
  if (!ext) { ext = EXTENSIONS[String(language).toLowerCase()] || 'txt'; base += '.' + ext; }
  if (!/^[a-z0-9]{1,8}$/.test(ext) || BLOCKED.has(ext)) return null;
  return base;
}

/** Writes `text` into `directory` and returns the name used. "name.ext" becomes "name (2).ext" if it exists. */
async function save(directory, name, text, language) {
  const clean = safeName(name, language);
  if (!clean) throw new Error('Choose a file name with a normal extension, like notes.md.');
  if (typeof text !== 'string') throw new Error('Nothing to save.');
  if (Buffer.byteLength(text) > MAX_BYTES) throw new Error('This is too large to save (1 MB limit).');
  await fs.mkdir(directory, { recursive: true });
  const extension = path.extname(clean), stem = clean.slice(0, clean.length - extension.length);
  for (let n = 1; n <= 50; n++) {
    const candidate = n === 1 ? clean : `${stem} (${n})${extension}`;
    const target = path.join(directory, candidate);
    if (path.dirname(target) !== path.resolve(directory) && path.dirname(target) !== directory) throw new Error('That file name is not allowed.');
    try { await fs.writeFile(target, text, { flag: 'wx' }); return candidate; }
    catch (error) { if (error.code !== 'EEXIST') throw new Error('The file could not be saved.'); }
  }
  throw new Error('Too many files with this name. Choose another name.');
}

module.exports = { safeName, save, MAX_BYTES };
