'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { sha512Crypt } = require('./sha512-crypt.cjs');
test('SHA-512 crypt matches the specification and OpenSSL', () => {
  // Test vectors from Drepper's SHA-crypt specification, and one checked against `openssl passwd -6`.
  assert.equal(sha512Crypt('Hello world!', 'saltstring'), '$6$saltstring$svn8UoSVapNtMuq1ukKS4tPQd8iKwSMHWjl/O817G3uBnIFNjnQJuesI68u4OTLiBFdcbYEdFCoEOfaS35inz1');
  assert.equal(sha512Crypt('Hello world!', 'saltstringsaltstring', 10000), '$6$rounds=10000$saltstringsaltst$OW1/O6BYHV6BcXZu8QVeXbDWra3Oeqh0sbHbbMCVNSnCM/UrjmM0Dp8vOuZeHBy/YTBmSK6H9qs/y3RnOaw5v.');
  assert.equal(sha512Crypt('pw-abc_123', 'abcdefgh12345678'), '$6$abcdefgh12345678$xoheLHqVedz6K19K6Q665pOCtp09PXsH/6D7t6xtqhUVINJmH/suEE9onSYKWgpUhl29DOkNWe745r8WYt5370');
});
