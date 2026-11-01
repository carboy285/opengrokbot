#!/usr/bin/env python3
"""Static project consistency checks. This does not compile Swift or run XCTest.
Install check-only dependencies: pip install -r scripts/check-requirements.txt
"""
import json
from pathlib import Path
import plistlib
import sys
import xml.etree.ElementTree as ET
from openstep_parser import OpenStepDecoder
from tree_sitter import Language, Parser
import tree_sitter_swift

root = Path(__file__).resolve().parents[1]
failures = []
parser = Parser(Language(tree_sitter_swift.language()))
swift_files = sorted(root.glob('GrokBot/**/*.swift')) + sorted(root.glob('GrokBotTests/*.swift')) + sorted(root.glob('GrokBotMac/**/*.swift')) + sorted(root.glob('GrokBotMacUITests/*.swift')) + sorted(root.glob('ComposioBridge/*.swift'))
for path in swift_files:
    tree = parser.parse(path.read_bytes())
    nodes = [tree.root_node]
    while nodes:
        node = nodes.pop()
        if node.type == 'ERROR' or node.is_missing:
            failures.append(f'{path.relative_to(root)}:{node.start_point.row+1}: Swift syntax {node.type}')
        nodes.extend(node.children)
with (root/'GrokBot.xcodeproj/project.pbxproj').open() as stream:
    project = OpenStepDecoder.ParseFromFile(stream)
objects = project['objects']
assert project['rootObject'] in objects
references = set()
for key, obj in objects.items():
    if obj['isa'] == 'PBXFileReference' and obj.get('sourceTree') == '<group>':
        path = root/obj['path']
        if not path.exists(): failures.append(f'Missing project file: {obj["path"]}')
        references.add(path)
    if obj['isa'] in ('PBXSourcesBuildPhase', 'PBXResourcesBuildPhase'):
        for file_id in obj['files']:
            assert objects[file_id]['fileRef'] in objects
    if obj['isa'] == 'XCConfigurationList':
        for config in obj['buildConfigurations']: assert config in objects
for path in swift_files:
    if path not in references: failures.append(f'Swift file excluded from project: {path}')
for path in [root/'GrokBot/Resources/Info.plist', root/'GrokBot/Resources/PrivacyInfo.xcprivacy', root/'GrokBotMac/Resources/Info.plist', root/'GrokBotMac/Resources/GrokBotMac.entitlements']:
    with path.open('rb') as stream: plistlib.load(stream)
for path in root.glob('GrokBot/Resources/Assets.xcassets/**/Contents.json'):
    contents = json.loads(path.read_text())
    for asset in contents.get('images', []):
        if 'filename' in asset: assert (path.parent/asset['filename']).is_file()
for scheme_path in root.glob('GrokBot.xcodeproj/xcshareddata/xcschemes/*.xcscheme'):
    scheme = ET.parse(scheme_path)
    for reference in scheme.findall('.//BuildableReference'):
        assert reference.attrib['BlueprintIdentifier'] in objects
if failures:
    print('\n'.join(failures), file=sys.stderr)
    sys.exit(1)
print(f'PASS: {len(swift_files)} Swift files parse; {len(objects)} Xcode objects, scheme, resource paths, plists, and asset references are consistent.')
print('Static checks only. Xcode compilation, XCTest, UI rendering and device installation are not verified.')
