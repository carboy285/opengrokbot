#!/bin/bash
# Inspect a local installer without launching its app or reading user credentials.
set -euo pipefail
umask 077
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script requires macOS (hdiutil, codesign, and plutil)." >&2
  exit 1
fi
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 /path/to/Grok_Bot_0.78.1.dmg [new-output-directory]" >&2
  exit 1
fi
command -v python3 >/dev/null || { echo "Install Python 3.9+ first." >&2; exit 1; }
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
input_file="$(cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")"
output_dir="${2:-inspection/0.78.1}"
if [[ -e "$output_dir" || -L "$output_dir" ]]; then
  echo "Output directory must not exist: $output_dir" >&2
  exit 1
fi
mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
mount_dir="$(mktemp -d -t opengrokbot-inspect)"
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then hdiutil detach "$mount_dir" -quiet || true; fi
  rmdir "$mount_dir" 2>/dev/null || true
}
trap cleanup EXIT
shasum -a 256 "$input_file" > "$output_dir/installer.sha256"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount_dir" "$input_file" > "$output_dir/mount.txt"
mounted=1
app_path="$(find "$mount_dir" -maxdepth 2 -type d -name '*.app' -print -quit)"
if [[ -z "$app_path" ]]; then echo "No app bundle found; see mount.txt." >&2; exit 1; fi
python3 - "$app_path" "$output_dir" <<'PY'
import hashlib, json, plistlib, sys
from pathlib import Path
app, out = map(Path, sys.argv[1:])
with (app/'Contents/Info.plist').open('rb') as f:
    info = plistlib.load(f)
keys = ['CFBundleIdentifier','CFBundleName','CFBundleShortVersionString','CFBundleVersion','LSMinimumSystemVersion','CFBundleExecutable','CFBundleURLTypes']
metadata = {k:info[k] for k in keys if k in info}
archives = []
for archive in (app/'Contents/Resources').rglob('*.asar'):
    digest = hashlib.sha256()
    with archive.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024), b''): digest.update(block)
    archives.append({'path':str(archive.relative_to(app)),'bytes':archive.stat().st_size,'sha256':digest.hexdigest()})
metadata['archives'] = archives
(out/'bundle-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
PY
codesign -dv --verbose=4 "$app_path" > "$output_dir/signature.txt" 2>&1 || true
codesign --verify --deep --strict "$app_path" > "$output_dir/signature-verification.txt" 2>&1 || true
archive_path="$app_path/Contents/Resources/app.asar"
if [[ -f "$archive_path" ]]; then
  python3 "$script_dir/unpack_asar.py" "$archive_path" "$output_dir/asar"
else
  echo "No app.asar at the standard Electron path. See bundle-metadata.json."
fi
cat > "$output_dir/READ-ME.txt" <<'NOTE'
Local static inspection only. No app code was launched and no user account
storage or Keychain was read. Extracted application code may be proprietary;
keep it local and do not commit it. Review the metadata and archive index first.
Locate versioned protocol schemas, auth/callback handling, transports and errors.
Strings in a binary are leads, not evidence of a supported public API.
NOTE
printf 'Inspection saved to %s\n' "$output_dir"
