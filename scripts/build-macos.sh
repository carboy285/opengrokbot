#!/bin/bash
# Produce a universal native .app and a drag-to-Applications DMG on a Mac.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo "A Mac with Xcode is required to compile the native app and create its DMG." >&2
  exit 1
fi
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
cd "$repo_dir"
output_dir="${1:-$repo_dir/artifacts/macos}"
mkdir -p "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
derived_dir="$output_dir/DerivedData"
identity="${MACOS_SIGN_IDENTITY:--}"
if [[ "$identity" == '-' ]]; then
  echo 'Building an ad-hoc signed local development app (not notarized).'
fi
xcodebuild -project GrokBot.xcodeproj -scheme GrokBotMac \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_dir" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" \
  CODE_SIGNING_REQUIRED=YES build
app_path="$derived_dir/Build/Products/Release/OpenGrokBot.app"
if [[ ! -d "$app_path" ]]; then echo "Build did not produce OpenGrokBot.app" >&2; exit 1; fi
codesign --verify --deep --strict "$app_path"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
image_path="$output_dir/OpenGrokBot-${version}-mac-universal.dmg"
if [[ -e "$image_path" ]]; then echo "Refusing to overwrite $image_path" >&2; exit 1; fi
stage_dir="$(mktemp -d -t opengrokbot-dmg)"
trap 'rm -rf -- "$stage_dir"' EXIT
# ditto preserves the bundle's resources, code signature, and executable modes.
ditto "$app_path" "$stage_dir/OpenGrokBot.app"
ln -s /Applications "$stage_dir/Applications"
cat > "$stage_dir/Read Me.txt" <<'NOTE'
Drag OpenGrokBot to Applications.
This is an independent local-preview build. Live Grok Bot access is not implemented.
If ad-hoc signed, macOS may block opening it. Use a locally built copy or a
Developer ID signed and notarized release; do not disable Gatekeeper globally.
NOTE
hdiutil create -volname 'OpenGrokBot' -srcfolder "$stage_dir" -format UDZO -ov "$image_path"
hdiutil verify "$image_path"
if [[ -n "${MACOS_NOTARY_PROFILE:-}" ]]; then
  if [[ "$identity" == '-' ]]; then echo 'Notarization requires a Developer ID identity.' >&2; exit 1; fi
  xcrun notarytool submit "$image_path" --keychain-profile "$MACOS_NOTARY_PROFILE" --wait
  xcrun stapler staple "$image_path"
fi
shasum -a 256 "$image_path" > "$image_path.sha256"
printf 'DMG created: %s\n' "$image_path"
