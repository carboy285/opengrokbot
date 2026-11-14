#!/bin/sh
set -e
node /app/docker/entrypoint.cjs
# A virtual screen stands in for a monitor; Electron needs one even though nobody looks at it.
exec xvfb-run -a --server-args="-screen 0 1280x800x24" /app/node_modules/.bin/electron --no-sandbox --disable-gpu /app
