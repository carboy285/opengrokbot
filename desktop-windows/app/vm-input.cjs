'use strict';
/**
 * Clicks, typing and keys sent into the shared VM by running xdotool inside it, through the same guest-command channel Bots use.
 * Needs xdotool and an Xorg (not Wayland) desktop session in the VM.
 */
const KEYS = ['Return', 'Tab', 'Escape', 'BackSpace', 'Up', 'Down', 'Left', 'Right'];
// Finds the logged-in desktop's display and permission file, then runs xdotool with the arguments after it. Nothing is spliced into the script.
const LAUNCHER = 'export DISPLAY=:0; for f in /run/user/*/gdm/Xauthority /home/*/.Xauthority /root/.Xauthority; do if [ -f "$f" ]; then export XAUTHORITY="$f"; break; fi; done; exec "$@"';
const run = words => ['/bin/sh', '-c', LAUNCHER, 'sh', 'xdotool', ...words];
const NEEDS = 'Clicking and typing need xdotool and an Xorg desktop session in the VM (Ubuntu: sudo apt install xdotool, and sign in with “Ubuntu on Xorg”).';

const geometry = () => run(['getdisplaygeometry']);
function click(x, y) { return Number.isInteger(x) && Number.isInteger(y) && x >= 0 && y >= 0 && x < 20000 && y < 20000 ? run(['mousemove', String(x), String(y), 'click', '1']) : null; }
function type(text) { const clean = String(text ?? '').slice(0, 500); return clean && !clean.includes('\0') ? run(['type', '--delay', '30', '--', clean]) : null; }
function key(name) { return KEYS.includes(name) ? run(['key', name]) : null; }
/** "Linux guest exit 0:\n1920 1080" becomes [1920, 1080]. */
function parseGeometry(output) {
  const numbers = (String(output).match(/\d+/g) || []).map(Number); if (numbers.length < 2) return null;
  const [w, h] = numbers.slice(-2); return w > 100 && h > 100 ? [w, h] : null;
}
/** True when the guest output says the command did not work. */
const failed = output => /exit [1-9]/.test(String(output)) || /can't open display|not found/i.test(String(output));

module.exports = { KEYS, NEEDS, geometry, click, type, key, parseGeometry, failed };
