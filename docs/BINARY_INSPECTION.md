# Inspect the local 0.78.1 installer

The supplied DMG could not be downloaded by the 32 MiB-limited transfer tool. These tools let you inspect it on the Mac where the original file exists. They inspect packaged application files only. They do not launch Grok Bot, connect to its services, read installed profiles, export login sessions, or access Keychain.

## Run on macOS

Install Python 3.9+ if it is not present, open Terminal in this repository, then run:

```bash
./scripts/inspect-dmg.sh "$HOME/Downloads/Grok_Bot_0.78.1.dmg" inspection/0.78.1
```

The output directory must not already exist. Use a new directory for each artifact so evidence is not overwritten. The command uses macOS `hdiutil`, `codesign`, and `shasum`; it mounts read-only without opening Finder or the app, and attempts to detach on exit. The installer must be a plain disk image containing an `.app` bundle within two directory levels. Encrypted/multipart installers and unusual layouts are not handled automatically.

Outputs:

- `installer.sha256`: identity of the original input.
- `bundle-metadata.json`: selected Info.plist values, registered URL schemes, archive paths/sizes/checksums. The file records the actual bundle version, independently of the installer filename.
- `signature.txt` and `signature-verification.txt`: signing diagnostics. Review them; their presence alone does not mean verification succeeded. Signing is not a guarantee that network protocols are public or supported.
- `asar/`: extracted packaged code if `Contents/Resources/app.asar` exists.
- `asar-index.json`: paths, sizes, offsets, and hashes of extracted files; native “unpacked” entries are listed but not copied.

The extraction directory is ignored by Git. Extracted files are not executable. Proprietary vendor code and images must not be committed as part of this MIT project. The script does not reconstruct original authored source from minified code or guarantee that source maps are available.

## Smaller artifact transfer

On your Mac, the script produces a normal extracted directory. Start by reviewing `bundle-metadata.json` and `asar-index.json`. Those small files establish which inputs exist; selected packaged protocol/auth files can be inspected next. Keep account details, tokens, cookie jars, and local application storage out of any shared files. App bundle metadata is different from a signed-in user's settings and credentials.

If you already copied the packaged archive from the read-only mount, extraction can run on any platform with Python:

```bash
python3 scripts/unpack_asar.py /absolute/path/to/app.asar inspection/extracted
```

Use a destination that does not exist. The extractor bounds header and output size, rejects traversal/symlinks/overlapping ranges, and does not follow links or run JavaScript. It intentionally does not copy `app.asar.unpacked`; native binaries can be inspected separately on macOS when necessary. Malformed or unsupported archives fail with an error. The synthetic unit tests cover the implemented format, not the supplied 0.78.1 archive.

## Review order

1. Establish artifact identity and actual version before inferring compatibility.
2. Read packaged manifest metadata and locate generated schemas, transport entry points, browser authentication handling, and relevant source maps if shipped. Treat filenames and strings as leads.
3. Trace a request from the renderer through preload/desktop IPC to its actual service transport. Separate local IPC, execution daemons, telemetry, plugin servers, and the Bot control plane.
4. Recover request, response, event, and error contracts from their callers and decoders. Record exact file paths and hashes for each claim.
5. Determine whether authentication can be supported by an independent app without collecting another client's session or bypassing access controls.
6. Implement only evidenced operations, then verify with an authorized account and a phone-reachable connection. Test approval enforcement and failure/reconnection behavior before declaring support.

The result of this process should update `HARNESS.md` and the compatibility declaration. Finding an endpoint string is insufficient to mark the integration connected.
