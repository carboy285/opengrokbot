'use strict';
// Password-encrypted workspace backups. Same envelope as the Mac app (BackupCrypto.swift):
// PBKDF2-SHA256 (600,000 rounds) -> AES-256-GCM, ciphertext stored as ct || 16-byte tag.
const { pbkdf2Sync, randomBytes, createCipheriv, createDecipheriv } = require('node:crypto');

const ROUNDS = 600000;

function deriveKey(password, salt, rounds) { return pbkdf2Sync(Buffer.from(password, 'utf8'), salt, rounds, 32, 'sha256'); }

function encryptBackup(value, password, platform = 'windows') {
  if (typeof password !== 'string' || password.length < 8) throw new Error('Use a password of at least 8 characters.');
  const salt = randomBytes(16), iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', deriveKey(password, salt, ROUNDS), iv);
  const body = Buffer.concat([cipher.update(Buffer.from(JSON.stringify(value), 'utf8')), cipher.final(), cipher.getAuthTag()]);
  return JSON.stringify({ format: 'opengrokbot-backup', version: 1, platform, createdAt: new Date().toISOString(), kdf: 'pbkdf2-sha256', iterations: ROUNDS, salt: salt.toString('base64'), iv: iv.toString('base64'), ciphertext: body.toString('base64') });
}

function decryptBackup(text, password) {
  let envelope;
  try { envelope = JSON.parse(text); } catch { throw new Error('This is not an OpenGrokBot backup.'); }
  if (envelope?.format !== 'opengrokbot-backup' || envelope.version !== 1 || envelope.kdf !== 'pbkdf2-sha256') throw new Error('This is not an OpenGrokBot backup.');
  if (!Number.isInteger(envelope.iterations) || envelope.iterations < 100000 || envelope.iterations > 5000000) throw new Error('This backup uses unsupported settings.');
  const salt = Buffer.from(envelope.salt || '', 'base64'), iv = Buffer.from(envelope.iv || '', 'base64'), body = Buffer.from(envelope.ciphertext || '', 'base64');
  if (salt.length < 16 || iv.length !== 12 || body.length < 17) throw new Error('This backup is damaged.');
  try {
    const decipher = createDecipheriv('aes-256-gcm', deriveKey(String(password), salt, envelope.iterations), iv);
    decipher.setAuthTag(body.subarray(body.length - 16));
    const plain = Buffer.concat([decipher.update(body.subarray(0, body.length - 16)), decipher.final()]);
    return { platform: envelope.platform, workspace: JSON.parse(plain.toString('utf8')) };
  } catch { throw new Error('Wrong password, or the backup was changed.'); }
}

module.exports = { encryptBackup, decryptBackup, ROUNDS };
