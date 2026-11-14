const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

test('companions are valid Bot templates that stay honest about being AI', async () => {
  const { companions, companionById } = await import(pathToFileURL(path.join(__dirname, '../renderer/companions.js')).href);
  assert.ok(companions.length >= 6);
  assert.equal(new Set(companions.map(x => x.id)).size, companions.length);
  const shapes = new Set(['circle','cloud','square','sparkle','flower','heart','clover','droplet','capsule','triangle','pebble','star','hexagon','fruit']), colors = new Set(['purple', 'pink', 'red', 'orange', 'amber', 'green', 'teal', 'blue', 'gray', 'black']);
  for (const item of companions) {
    assert.ok(item.name.length > 0 && item.name.length <= 200, item.id);
    assert.ok(item.purpose.length <= 2000, `${item.id} purpose fits the form's 2000 limit`);
    assert.ok(colors.has(item.color), item.id);
    assert.ok(shapes.has(item.shape), item.id);
    assert.match(item.purpose, /AI assistant/, item.id);
    assert.match(item.purpose, /never claim to be human/, item.id);
  }
  assert.equal(companionById('chef').name, 'Home Chef');
  assert.equal(companionById('nope'), null);
});
