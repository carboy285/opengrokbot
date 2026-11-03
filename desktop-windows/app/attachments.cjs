'use strict';
const { mkdir, writeFile, copyFile, lstat } = require('node:fs/promises');
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

const LOCAL_MAX_FILES = 10;
const LOCAL_MAX_BYTES = 20_000_000;
const DATA_EXTENSIONS = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/gif': 'gif', 'image/webp': 'webp' };
const NAME = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-[^/\\]{1,60}$/i;

function cleanName(value) {
  const base = path.basename(String(value || 'file')).replace(/[\u0000-\u001f/\\:*?"<>|]/g, '_').trim();
  return (base || 'file').slice(0, 40);
}

/** Copies files the user picked on this PC into <directory>/Attachments. Returns stored names. */
async function copyLocalFiles(directory, sources) {
  if (!Array.isArray(sources) || !sources.length || sources.length > LOCAL_MAX_FILES) throw new Error('Choose up to 10 files.');
  const folder = path.join(directory, 'Attachments');
  await mkdir(folder, { recursive: true, mode: 0o700 });
  const names = [];
  for (const source of sources) {
    const info = await lstat(source);
    if (!info.isFile() || info.size > LOCAL_MAX_BYTES) throw new Error('Choose regular files under 20 MB.');
    const name = `${randomUUID()}-${cleanName(source)}`;
    await copyFile(source, path.join(folder, name));
    names.push(name);
  }
  return names;
}

/** Saves an image pasted from the clipboard. */
async function saveDataFile(directory, mime, base64) {
  const extension = DATA_EXTENSIONS[mime];
  if (!extension || typeof base64 !== 'string' || base64.length > 27_000_000) throw new Error('Unsupported image.');
  const bytes = Buffer.from(base64, 'base64');
  if (!bytes.length || bytes.length > LOCAL_MAX_BYTES) throw new Error('Unsupported image.');
  const folder = path.join(directory, 'Attachments');
  await mkdir(folder, { recursive: true, mode: 0o700 });
  const name = `${randomUUID()}-Pasted image.${extension}`;
  await writeFile(path.join(folder, name), bytes, { mode: 0o600 });
  return name;
}

/** Confirms every name is a stored attachment in this Bot folder (no paths, no traversal). */
async function existingNames(directory, names) {
  if (names === undefined || names === null) return [];
  if (!Array.isArray(names) || names.length > LOCAL_MAX_FILES) throw new Error('Too many attachments.');
  for (const name of names) {
    if (typeof name !== 'string' || !NAME.test(name) || path.basename(name) !== name) throw new Error('Invalid attachment.');
    if (!(await lstat(path.join(directory, 'Attachments', name))).isFile()) throw new Error('Missing attachment.');
  }
  return names;
}

function attachmentMessage(base, names) {
  if (!names.length) return base;
  const lead = base.trim() ? base : 'Please review the attached files.';
  return `${lead}\n\nAttached files in this Bot’s working folder:\n${names.map(name => `- Attachments/${name}`).join('\n')}\nUse your available tools to read these files; do not assume an image was viewed.`;
}

module.exports = { saveRemoteImages, copyLocalFiles, saveDataFile, existingNames, attachmentMessage, MAX_COUNT, MAX_TOTAL_BYTES };
