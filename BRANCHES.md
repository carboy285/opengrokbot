# Source branches

All three branches descend from release tag `v0.7.4`. Existing file contents are unchanged; the only added file is this guide.

- `main-source`: complete original project plus this guide. Use for shared work, combined-platform workflows, and releases.
- `app/apple`: iPhone and Mac sources together, including `GrokBot.xcodeproj/`, `GrokBot/`, `GrokBotMac/`, `GrokBotTests/`, `GrokBotMacUITests/`, and `ComposioBridge/`. Excludes `desktop-windows/`, the Windows-only build/UI/smoke-test scripts, and `docs/WINDOWS.md`.
- `app/windows`: Windows/Electron app and its package manifests, all `scripts/`, `supabase/`, `docs/`, and `.github/workflows/`. Excludes the Apple source/project/test folders, `ComposioBridge/`, and the root iOS installation guide.

Shared infrastructure stays in both app branches: package metadata (needed for the shared cloud tests), database files, documentation, workflows, and the icon generator. Because existing contents must remain unchanged, cross-platform workflows, opposite-platform npm commands, and the icon generator may require missing platform folders; run combined-platform operations from `main-source`. The Windows branch deliberately retains Apple utility scripts and workflow definitions as requested; those Apple-specific tasks need `main-source` or `app/apple`.

`main` and all release tags are unchanged. These are source branches, not new releases.
