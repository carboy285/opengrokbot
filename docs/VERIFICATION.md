# Verification results

The local workspace is Linux x86_64, without Xcode. Native platform builds run in this repository's GitHub Actions workflows. Live Grok Bot interoperability remains unverified on every platform.

## Completed checks

| Check | Result and evidence |
| --- | --- |
| Native macOS unit tests | 9 tests passed with Xcode 26.6 on macOS 26 (also passed with Xcode 26.3 earlier): persistence, preview state, save failure, connection-draft rejection, unavailable integration, and Keychain create/read/replace/delete |
| Universal macOS build | Passed for `arm64` and `x86_64`; `lipo` created the universal executable |
| macOS packaging | `codesign --verify --deep --strict` and `hdiutil verify` passed; a compressed DMG and SHA-256 file were produced |
| Native macOS UI | One real-application UI test passed, checking the conversation, Connect Apps, and Settings; three window screenshots were retained |
| macOS 26 build | Native compilation, unit tests, and packaging passed on an OS that supports Liquid Glass |
| iOS simulator | All 9 XCTest tests passed with the signed simulator host, including the Keychain round trip |
| Windows Setup | NSIS x64 installer built successfully on a Windows runner |
| Native Windows app smoke test | Passed: actual Electron launch, isolated renderer, invalid IPC rejection, local-note persistence after relaunch, encrypted vault round trip, and no plaintext secret in the vault JSON |
| Desktop UI behavior | Browser checks passed for persistence, Bot creation, text escaping, failed-save draft recovery, app catalog filtering, truthful connection status, themes, and reduced motion |
| Windows local model tests | 2 tests passed, including multiple malformed-state cases |
| Installer extraction helper | 4 Python tests passed with synthetic ASAR archives |
| Static Apple project checks | Swift syntax parsed; Xcode object/resource/scheme references and property lists checked |
| Shell and JavaScript syntax | Packaging/inspection shell scripts and Electron/renderer scripts parsed successfully |

Final native Mac unit/UI tests, universal build, and DMG verification: [workflow run 41257537906](https://github.com/carboy285/opengrokbot/actions/runs/41257537906), source commit `c24ab6a34075604c1d6ff3bf637a8881de6cb82e`. This run also verifies the final Windows focus-race fix and produces its Setup EXE.

Initial successful native Mac build and logs: [workflow run 41256033597](https://github.com/carboy285/opengrokbot/actions/runs/41256033597). It produced `OpenGrokBot-0.2.0-mac-universal.dmg` after nine native tests passed. [Subsequent desktop CI](https://github.com/carboy285/opengrokbot/actions/runs/41256440777) built the Mac app on macOS 26 and the Windows installer. The draft PR contains later build/test revisions and artifacts.

## Native visual review and iOS status

Actual macOS application-window captures were successfully produced by `GrokBotMacUITests/MacUITests.swift`. The test launches the application and checks the conversation and reference panels before retaining screenshots in the XCTest result bundle. View bitmap caching was unsuitable for scrolling content, so it is not used as visual proof. The three captures were inspected and are saved in `docs/screenshots/`. They show the responsive layout on the runner’s smaller display. This is not a claim of pixel-perfect equality with the larger reference images.

The iOS pipeline found a SwiftUI `Section` initializer error in Settings, then identified missing Keychain entitlements in the unsigned simulator test host. Both were corrected; the simulator host is now ad-hoc signed with explicit application/keychain entitlements. The final simulator run passed all nine tests. [iOS workflow results](https://github.com/carboy285/opengrokbot/actions/runs/41257537876) record the signed-host build and XCTest results. Physical-iPhone signing, installation, and live service operation have not been tested.

## Commands

macOS CI runs:

```bash
xcodebuild -project GrokBot.xcodeproj -scheme GrokBotMac \
  -configuration Debug -destination 'platform=macOS' \
  -resultBundlePath artifacts/macos-tests.xcresult \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- test
xcrun xcresulttool export attachments --path artifacts/macos-tests.xcresult \
  --output-path artifacts/visuals
./scripts/build-macos.sh
```

Windows CI runs `npm ci`, `npm run test:desktop`, `node scripts/test-electron.cjs`, and `npm run dist:windows`.

Local Linux checks include `python3 scripts/check_project.py`, `python3 -m unittest discover -s scripts -p 'test_*.py' -v`, `bash -n scripts/build-macos.sh`, `bash -n scripts/inspect-dmg.sh`, `npm run test:desktop`, and `npm run test:ui` with `/usr/bin/chromium`. The UI test uses the installed browser; it requires no browser download.

## Limits

- No vendor DMG bytes have been inspected. The attachment transfer tool returned `file exceeds the executor transfer limit of 32 MiB`. Original Mac attachment paths do not exist on the Linux host.
- The reference installer inspection wrapper has not run against the supplied 0.78.1 artifact. ASAR tests use synthetic inputs.
- Mac CI packages are ad-hoc signed, not Developer ID signed or notarized. Signature verification does not establish Gatekeeper acceptance on a downloaded copy.
- The Windows installer is unsigned. Installer generation and app smoke tests do not establish a complete install/uninstall review on a user's PC.
- A local Linux NSIS build stopped because Wine was unavailable; successful Setup builds use Windows CI.
- No physical iPhone has been used. Simulator results do not prove device signing or installation.
- No real login, account synchronization, agent execution, tools, approvals, cloud computer control, voice, connectors, or streaming has been verified. Supported harness versions remain **none**.
