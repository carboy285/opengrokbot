'use strict';
// Prepares a headless OpenGrokBot container: turns on web access from environment variables, then exits.
// Needs OPENGROKBOT_WEB_PASSWORD (10+ characters). OPENGROKBOT_WEB_USER defaults to "admin".
// OPENGROKBOT_PLUGINS is an optional comma-separated list of plugin names to allow (see docs/PLUGINS.md).
const fs = require('node:fs');
const path = require('node:path');
const { hashPassword, passwordProblem, USER } = require('../desktop-windows/app/web-access.cjs');

const dataDir = process.env.OPENGROKBOT_DATA_DIR || '/data';
const user = process.env.OPENGROKBOT_WEB_USER || 'admin';
const password = process.env.OPENGROKBOT_WEB_PASSWORD || '';
const problem = passwordProblem(password);
if (problem) { console.error('OPENGROKBOT_WEB_PASSWORD is not usable: ' + problem); process.exit(2); }
if (!USER.test(user)) { console.error('OPENGROKBOT_WEB_USER may use letters, numbers and . _ @ - (3 to 64 characters).'); process.exit(2); }

fs.mkdirSync(dataDir, { recursive: true });
const file = path.join(dataDir, 'settings.json');
let settings = {};
try { settings = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {}
settings.webAccess = { ...(settings.webAccess || {}), enabled: true, username: user, passwordHash: hashPassword(password), mode: 'wifi' };
const plugins = (process.env.OPENGROKBOT_PLUGINS || '').split(',').map(x => x.trim()).filter(Boolean);
if (plugins.length) settings.plugins = { ...(settings.plugins || {}), allowed: plugins };
fs.writeFileSync(file, JSON.stringify(settings), { mode: 0o600 });
console.log(`Web access is on for user "${user}" at port 8765.`);
