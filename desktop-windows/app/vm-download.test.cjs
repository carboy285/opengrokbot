const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { downloadVerified, ensureUbuntuISO } = require('./vm-download.cjs');

const body = Buffer.from('pretend this is a six gigabyte disk image'.repeat(50));
const sha = createHash('sha256').update(body).digest('hex');
const reply = (status, data, headers = {}) => new Response(data, { status, headers: { 'content-length': String(data.length), ...headers } });

test('a download is verified, kept, and reused without downloading again', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'vmdl-')); const dest = path.join(dir, 'a.iso'); let calls = 0;
  const fetcher = async () => { calls++; return reply(200, body); };
  assert.equal(await downloadVerified({ url: 'https://x.example/a.iso', dest, sha256: sha, fetcher }), dest);
  assert.deepEqual(await fs.readFile(dest), body);
  await downloadVerified({ url: 'https://x.example/a.iso', dest, sha256: sha, fetcher }); assert.equal(calls, 1);
});

test('a partly finished download resumes from where it stopped', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'vmdl-')); const dest = path.join(dir, 'b.iso');
  await fs.writeFile(dest + '.part', body.subarray(0, 700)); let range = null;
  const fetcher = async (_url, options) => { range = options.headers.Range; return reply(206, body.subarray(700)); };
  await downloadVerified({ url: 'https://x.example/b.iso', dest, sha256: sha, fetcher });
  assert.equal(range, 'bytes=700-'); assert.deepEqual(await fs.readFile(dest), body);
});

test('a download with the wrong checksum is thrown away and reported', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'vmdl-')); const dest = path.join(dir, 'c.iso');
  await assert.rejects(downloadVerified({ url: 'https://x.example/c.iso', dest, sha256: 'f'.repeat(64), fetcher: async () => reply(200, body) }), /checksum/);
  await assert.rejects(fs.stat(dest)); await assert.rejects(fs.stat(dest + '.part'));
  await assert.rejects(downloadVerified({ url: 'https://x.example/d.iso', dest, sha256: sha, fetcher: async () => reply(404, Buffer.from('no')) }), /HTTP 404/);
});

test('the Ubuntu desktop ISO is chosen from the published checksums', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'vmdl-')); const urls = [];
  const sums = `${sha} *ubuntu-24.04.3-desktop-amd64.iso\n${'0'.repeat(64)} *ubuntu-24.04.3-live-server-amd64.iso\n`;
  const fetcher = async url => { urls.push(url); return url.endsWith('SHA256SUMS') ? reply(200, Buffer.from(sums)) : reply(200, body); };
  const file = await ensureUbuntuISO({ root: dir, fetcher });
  assert.equal(path.basename(file), 'ubuntu-24.04.3-desktop-amd64.iso'); assert.ok(urls.some(u => u.endsWith('ubuntu-24.04.3-desktop-amd64.iso')));
});
