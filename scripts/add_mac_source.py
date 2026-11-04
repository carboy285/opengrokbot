#!/usr/bin/env python3
"""Register new GrokBotMac Swift files in GrokBot.xcodeproj without regenerating the project.

Usage: scripts/add_mac_source.py GrokBotMac/Connections/Example.swift ...
Mirrors how GrokBotMac/Features/MacVaultView.swift is registered: file reference, build file,
GrokBotMac group child and GrokBotMac sources build phase entry. Idempotent.
"""
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'GrokBot.xcodeproj/project.pbxproj'
ANCHOR = 'GrokBotMac/Features/MacVaultView.swift'

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def main(paths):
    text = PROJECT.read_text()
    anchor_ref = re.search(r'"([0-9A-F]{24})" = \{\n\t\t\t"isa" = "PBXFileReference";\n\t\t\t"lastKnownFileType" = "sourcecode.swift";\n\t\t\t"path" = "%s";' % re.escape(ANCHOR), text)
    if not anchor_ref:
        sys.exit('Anchor file reference not found.')
    ref_id = anchor_ref.group(1)
    build = re.search(r'"([0-9A-F]{24})" = \{\n\t\t\t"isa" = "PBXBuildFile";\n\t\t\t"fileRef" = "%s";' % ref_id, text)
    if not build:
        sys.exit('Anchor build file not found.')
    build_id = build.group(1)
    for path in paths:
        if not (ROOT / path).is_file():
            sys.exit(f'Missing file: {path}')
        if f'"path" = "{path}";' in text:
            continue
        new_ref, new_build = uid('file:' + path), uid('build:' + path)
        objects = (f'\t\t"{new_ref}" = {{\n\t\t\t"isa" = "PBXFileReference";\n\t\t\t"lastKnownFileType" = "sourcecode.swift";\n\t\t\t"path" = "{path}";\n\t\t\t"sourceTree" = "<group>";\n\t\t}};\n'
                   f'\t\t"{new_build}" = {{\n\t\t\t"isa" = "PBXBuildFile";\n\t\t\t"fileRef" = "{new_ref}";\n\t\t}};\n')
        # 1. objects, inserted after the anchor's build file object
        end = text.index('\t\t};\n', build.end()) + len('\t\t};\n')
        text = text[:end] + objects + text[end:]
        # 2. group child, after the anchor's reference in the GrokBotMac group
        child = f'\t\t\t\t"{ref_id}",\n'
        assert text.count(child) == 1, 'Anchor group child not unique'
        text = text.replace(child, child + f'\t\t\t\t"{new_ref}",\n')
        # 3. sources build phase entry, after the anchor's build file
        entry = f'\t\t\t\t"{build_id}",\n'
        assert text.count(entry) == 1, 'Anchor sources entry not unique'
        text = text.replace(entry, entry + f'\t\t\t\t"{new_build}",\n')
        print('Added', path)
    PROJECT.write_text(text)

if __name__ == '__main__':
    main(sys.argv[1:])
