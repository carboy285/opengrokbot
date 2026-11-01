const PREFIX = 'https://github.com/carboy285/opengrokbot/releases/';
function version(value) { const match = /^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(value || ''); return match ? match.slice(1, 4).map(Number) : null; }
function newer(next, current) { const a = version(next), b = version(current); if (!a || !b) return false; for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i]; return false; }
function trusted(url) { return typeof url === 'string' && url.startsWith(PREFIX) && !new URL(url).username && !new URL(url).password; }
async function check(current, fetchImpl = fetch) {
  const response = await fetchImpl('https://api.github.com/repos/carboy285/opengrokbot/releases?per_page=20', { redirect: 'error', signal: AbortSignal.timeout(15000), headers: { Accept: 'application/vnd.github+json' } });
  if (!response.ok) throw new Error('Updates could not be reached. Try again later.');
  const releases = await response.json(); if (!Array.isArray(releases)) throw new Error('Invalid update response.');
  const release = releases.filter(x => !x.draft && version(x.tag_name) && trusted(x.html_url)).sort((a, b) => newer(a.tag_name, b.tag_name) ? -1 : newer(b.tag_name, a.tag_name) ? 1 : 0)[0];
  return { current, available: !!release && newer(release.tag_name, current), version: release?.tag_name || current, prerelease: !!release?.prerelease, url: release?.html_url || PREFIX.slice(0, -1), checkedAt: new Date().toISOString() };
}
module.exports = { check, newer, trusted };
