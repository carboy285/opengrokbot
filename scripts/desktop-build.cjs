// Keep signing booleans in a config object: npm/PowerShell can split dotted CLI flags.
const { build } = require('../package.json');
const signed = process.env.SIGNED === 'true';
module.exports = { ...build, forceCodeSigning: signed, win: { ...build.win, signExecutable: signed } };
