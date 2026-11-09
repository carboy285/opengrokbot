'use strict';
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const { createHash } = require('node:crypto');
const tools = require('./vm-tools.cjs');

const sha256File = file => new Promise((resolve, reject) => {
  const hash = createHash('sha256'); const stream = fs.createReadStream(file);
  stream.on('data', chunk => hash.update(chunk)); stream.on('error', reject); stream.on('end', () => resolve(hash.digest('hex')));
});

/**
 * Downloads a file, resuming a partly finished download, and only keeps it if its SHA-256 matches. A file that is already there
 * and matches is reused. `onProgress({ received, total })` is called about once a second.
 */
async function downloadVerified({ url, dest, sha256, onProgress = () => {}, fetcher = fetch }) {
  await fsp.mkdir(path.dirname(dest), { recursive: true });
  try { if (await sha256File(dest) === sha256) return dest; await fsp.unlink(dest); } catch {}
  const part = dest + '.part';
  let have = 0; try { have = (await fsp.stat(part)).size; } catch {}
  const request = async from => fetcher(url, { headers: from ? { Range: `bytes=${from}-` } : {}, redirect: 'follow' });
  let response = await request(have);
  if (response.status === 416) { await fsp.unlink(part).catch(() => {}); have = 0; response = await request(0); }
  if (!response.ok) throw new Error(`The download failed (HTTP ${response.status}).`);
  const resumed = response.status === 206 && have > 0;
  if (!resumed) have = 0;
  const total = have + (Number(response.headers.get('content-length')) || 0);
  const out = fs.createWriteStream(part, { flags: resumed ? 'a' : 'w' });
  let received = have, last = 0;
  try {
    for await (const chunk of response.body) {
      if (!out.write(chunk)) await new Promise(resolve => out.once('drain', resolve));
      received += chunk.length;
      if (Date.now() - last > 1000) { last = Date.now(); onProgress({ received, total }); }
    }
  } finally { await new Promise(resolve => out.end(resolve)); }
  onProgress({ received, total: total || received });
  if (await sha256File(part) !== sha256) { await fsp.unlink(part).catch(() => {}); throw new Error('The download did not match its published checksum, so it was thrown away. Try again.'); }
  await fsp.rename(part, dest);
  return dest;
}

const text = async (url, fetcher) => { const response = await fetcher(url, { redirect: 'follow' }); if (!response.ok) throw new Error(`Could not read ${new URL(url).host} (HTTP ${response.status}).`); return response.text(); };

/** The current Ubuntu 24.04 desktop ISO, downloaded into <root>/downloads and checked against Ubuntu's SHA256SUMS. */
async function ensureUbuntuISO({ root, onProgress, fetcher = fetch }) {
  const base = 'https://releases.ubuntu.com/24.04/';
  const pick = tools.pickUbuntuDesktop(await text(base + 'SHA256SUMS', fetcher));
  if (!pick) throw new Error('The Ubuntu 24.04 desktop image was not found on releases.ubuntu.com. Choose an image yourself instead.');
  return downloadVerified({ url: base + pick.name, dest: path.join(root, 'downloads', pick.name), sha256: pick.sha256, onProgress, fetcher });
}

/** The current VirtualBox installer for Windows, downloaded and checked against VirtualBox's SHA256SUMS. */
async function ensureVirtualBoxInstaller({ dir, onProgress, fetcher = fetch }) {
  const base = 'https://download.virtualbox.org/virtualbox/';
  const version = tools.parseVBoxVersion(await text(base + 'LATEST-STABLE.TXT', fetcher));
  if (!version) throw new Error('The current VirtualBox version could not be read from virtualbox.org.');
  const pick = tools.pickVBoxWindows(await text(`${base}${version}/SHA256SUMS`, fetcher), version);
  if (!pick) throw new Error('The VirtualBox installer for Windows was not found on virtualbox.org.');
  return downloadVerified({ url: `${base}${version}/${pick.name}`, dest: path.join(dir, pick.name), sha256: pick.sha256, onProgress, fetcher });
}

module.exports = { downloadVerified, ensureUbuntuISO, ensureVirtualBoxInstaller, sha256File };
