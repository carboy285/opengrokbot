'use strict';
const { mkdir, writeFile } = require('node:fs/promises');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

const MAX_COUNT = 3;
const MAX_TOTAL_BYTES = 2_600_000;
const EXTENSIONS = { 'image/jpeg': 'jpg', 'image/png': 'png' };

function looksLikeImage(bytes, mime) {
  if (mime === 'image/png') return bytes.length > 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  return bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
}

/** Validates images from the iPhone and stores them in <directory>/Attachments. Returns stored file names. */
async function saveRemoteImages(directory, items) {
  if (!Array.isArray(items) || items.length === 0) return [];
  if (items.length > MAX_COUNT) throw new Error('Too many images.');
  const decoded = items.map(item => {
    const extension = EXTENSIONS[item?.mime];
    if (!extension || typeof item.data !== 'string' || item.data.length > 4_000_000) throw new Error('Unsupported image.');
    const bytes = Buffer.from(item.data, 'base64');
    if (!bytes.length || !looksLikeImage(bytes, item.mime)) throw new Error('Unsupported image.');
    return { bytes, extension };
  });
  if (decoded.reduce((sum, item) => sum + item.bytes.length, 0) > MAX_TOTAL_BYTES) throw new Error('Images are too large.');
  const folder = path.join(directory, 'Attachments');
  await mkdir(folder, { recursive: true, mode: 0o700 });
  const names = [];
  for (const item of decoded) {
    const name = `${randomUUID()}-Photo.${item.extension}`;
    await writeFile(path.join(folder, name), item.bytes, { mode: 0o600 });
    names.push(name);
  }
  return names;
}

function attachmentMessage(base, names) {
  if (!names.length) return base;
  const lead = base.trim() ? base : 'Please review the attached files.';
  return `${lead}\n\nAttached files in this Bot’s working folder:\n${names.map(name => `- Attachments/${name}`).join('\n')}\nUse your available tools to read these files; do not assume an image was viewed.`;
}

module.exports = { saveRemoteImages, attachmentMessage, MAX_COUNT, MAX_TOTAL_BYTES };
