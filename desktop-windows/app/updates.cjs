const PREFIX = 'https://github.com/carboy285/opengrokbot/releases/';
const DOWNLOAD = PREFIX + 'download/';
const { createWriteStream } = require('node:fs');
const { rm } = require('node:fs/promises');
const { createHash } = require('node:crypto');
function version(value) { const match = /^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(value || ''); return match ? match.slice(1, 4).map(Number) : null; }
function newer(next, current) { const a = version(next), b = version(current); if (!a || !b) return false; for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i]; return false; }
function trusted(url) { return typeof url === 'string' && url.startsWith(PREFIX) && !new URL(url).username && !new URL(url).password; }
async function check(current, fetchImpl = fetch) {
  const response = await fetchImpl('https://api.github.com/repos/carboy285/opengrokbot/releases?per_page=20', { redirect: 'error', signal: AbortSignal.timeout(15000), headers: { Accept: 'application/vnd.github+json' } });
  if (!response.ok) throw new Error('Updates could not be reached. Try again later.');
  const releases = await response.json(); if (!Array.isArray(releases)) throw new Error('Invalid update response.');
  const release = releases.filter(x => !x.draft && version(x.tag_name) && trusted(x.html_url)).sort((a, b) => newer(a.tag_name, b.tag_name) ? -1 : newer(b.tag_name, a.tag_name) ? 1 : 0)[0];
  const installer = (release?.assets || []).find(x => /-Windows-x64-Setup\.exe$/.test(x?.name || '') && trustedDownload(x.browser_download_url));
  return { current, available: !!release && newer(release.tag_name, current), version: release?.tag_name || current, prerelease: !!release?.prerelease, url: release?.html_url || PREFIX.slice(0, -1), installer: installer ? { url: installer.browser_download_url, size: installer.size, digest: typeof installer.digest === 'string' ? installer.digest : null } : null, checkedAt: new Date().toISOString() };
}
function trustedDownload(url) {
  try { const parsed = new URL(url); return typeof url === 'string' && url.startsWith(DOWNLOAD) && !parsed.username && !parsed.password && parsed.pathname.endsWith('.exe'); } catch { return false; }
}

/** Downloads the Windows installer, checking size and (when GitHub publishes one) its SHA-256 digest. */
async function download(installer, destination, fetchImpl = fetch) {
  if (!installer || !trustedDownload(installer.url)) throw new Error('Use the official project release.');
  const response = await fetchImpl(installer.url, { signal: AbortSignal.timeout(600000) });
  if (!response.ok || !response.body) throw new Error('The update could not be downloaded. Try again later.');
  const finalURL = response.url || installer.url;
  if (!/^https:\/\/(github\.com|objects\.githubusercontent\.com|release-assets\.githubusercontent\.com)\//.test(finalURL)) throw new Error('The update came from an unexpected address.');
  const hash = createHash('sha256'), out = createWriteStream(destination, { mode: 0o600 });
  let size = 0;
  try {
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > 400_000_000) throw new Error('The update is larger than expected.');
      hash.update(chunk);
      if (!out.write(chunk)) await new Promise(resolve => out.once('drain', resolve));
    }
    await new Promise((resolve, reject) => out.end(error => error ? reject(error) : resolve()));
    if (installer.size && size !== installer.size) throw new Error('The update download was incomplete.');
    if (installer.digest && installer.digest !== 'sha256:' + hash.digest('hex')) throw new Error('The update failed its integrity check.');
  } catch (error) { out.destroy(); await rm(destination, { force: true }); throw error; }
  return destination;
}

/**
 * Command line that runs the downloaded installer silently, then reopens the app.
 * Returns null when a path contains characters cmd.exe would treat specially; callers then fall back to the normal installer window.
 */
function installCommand(installer, exe) {
  const safe = value => typeof value === 'string' && /^[A-Za-z]:\\[^"&|<>^%!\r\n]+$/.test(value);
  if (!safe(installer) || !safe(exe)) return null;
  return { file: 'cmd.exe', args: ['/d', '/s', '/c', `"timeout /t 2 /nobreak >nul & "${installer}" /S && start "" "${exe}""`] };
}

module.exports = { check, newer, trusted, trustedDownload, download, installCommand };
