'use strict';
// SHA-512 crypt ($6$), as used in /etc/shadow, so the VM can be given a new password as a hash (never in plain text on a command line).
// Follows Ulrich Drepper's specification (https://www.akkadia.org/drepper/SHA-crypt.txt), default 5000 rounds.
const { createHash, randomBytes } = require('node:crypto');
const ALPHABET = './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const sha = (...parts) => { const h = createHash('sha512'); for (const p of parts) h.update(p); return h.digest(); };
function repeatTo(bytes, length) { const out = Buffer.alloc(length); for (let i = 0; i < length; i++) out[i] = bytes[i % bytes.length]; return out; }
function b64from24(b2, b1, b0, n) { let w = (b2 << 16) | (b1 << 8) | b0, s = ''; while (n-- > 0) { s += ALPHABET[w & 0x3f]; w >>= 6; } return s; }

function sha512Crypt(password, salt = randomSalt(), rounds = 5000) {
  const key = Buffer.from(String(password), 'utf8'), s = Buffer.from(String(salt).slice(0, 16), 'utf8');
  const b = sha(key, s, key);
  const aParts = [key, s, repeatTo(b, key.length)];
  for (let n = key.length; n > 0; n >>= 1) aParts.push(n & 1 ? b : key);
  let a = sha(...aParts);
  const dp = repeatTo(sha(...Array(key.length).fill(key)), key.length);
  const ds = repeatTo(sha(...Array(16 + a[0]).fill(s)), s.length);
  for (let i = 0; i < rounds; i++) {
    const parts = [i & 1 ? dp : a];
    if (i % 3) parts.push(ds);
    if (i % 7) parts.push(dp);
    parts.push(i & 1 ? a : dp);
    a = sha(...parts);
  }
  const order = [[0, 21, 42], [22, 43, 1], [44, 2, 23], [3, 24, 45], [25, 46, 4], [47, 5, 26], [6, 27, 48], [28, 49, 7], [50, 8, 29], [9, 30, 51], [31, 52, 10], [53, 11, 32], [12, 33, 54], [34, 55, 13], [56, 14, 35], [15, 36, 57], [37, 58, 16], [59, 17, 38], [18, 39, 60], [40, 61, 19], [62, 20, 41]];
  let out = '';
  for (const [x, y, z] of order) out += b64from24(a[x], a[y], a[z], 4);
  out += b64from24(0, 0, a[63], 2);
  return '$6$' + (rounds === 5000 ? '' : 'rounds=' + rounds + '$') + s.toString('utf8') + '$' + out;
}
function randomSalt() { return [...randomBytes(16)].map(x => ALPHABET[x & 0x3f]).join(''); }
module.exports = { sha512Crypt };
