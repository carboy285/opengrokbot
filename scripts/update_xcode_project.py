#!/usr/bin/env python3
"""Add/update the native macOS target while preserving the iOS project.
Development dependency: openstep-parser. The saved project requires no generator.
"""
from pathlib import Path
import hashlib
import json
from openstep_parser import OpenStepDecoder

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'GrokBot.xcodeproj/project.pbxproj'
with PROJECT.open() as stream:
    project = OpenStepDecoder.ParseFromFile(stream)
objects = project['objects']

def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(identity, **value):
    key = uid(identity)
    objects[key] = value
    return key

def reference(path, kind='sourcecode.swift'):
    key = uid(path)
    if key not in objects:
        add(path, isa='PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')
    return key

def phase(name, paths, kind):
    return add(name, isa=kind, buildActionMask='2147483647', files=[add(name+p, isa='PBXBuildFile', fileRef=reference(p)) for p in paths], runOnlyForDeploymentPostprocessing='0')

def configs(name, common):
    keys = [add(name+mode, isa='XCBuildConfiguration', buildSettings=common, name=mode) for mode in ['Debug','Release']]
    return add(name+'configs', isa='XCConfigurationList', buildConfigurations=keys, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')

def add_to_group(group_id, children):
    group = objects[group_id]
    group['children'] = list(dict.fromkeys(group['children'] + children))

# Shared controller contract/client and iOS controller sources.
remote_shared = ['GrokBot/Core/RemoteProtocol.swift'] + sorted(str(p.relative_to(ROOT)) for p in (ROOT/'GrokBot/Core').glob('Cloud*.swift'))
remote_ios = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'GrokBot/Remote').glob('*.swift'))
for path in remote_shared + remote_ios:
    key = reference(path)
    build = add('build'+path, isa='PBXBuildFile', fileRef=key)
    objects[uid('sources')]['files'] = list(dict.fromkeys(objects[uid('sources')]['files']+[build]))
    add_to_group(uid('appgroup'),[key])

# Add the shared glass source to the iOS target and source group.
avatar = 'GrokBot/Design/BotAppearance.swift'
reference(avatar)
avatar_build = add('build'+avatar, isa='PBXBuildFile', fileRef=uid(avatar))
objects[uid('sources')]['files'] = list(dict.fromkeys(objects[uid('sources')]['files']+[avatar_build]))
add_to_group(uid('appgroup'), [uid(avatar)])
glass = 'GrokBot/Design/GlassChrome.swift'
reference(glass)
team_shared = 'GrokBot/Core/BotTeamwork.swift'
reference(team_shared)
team_build = add('build'+team_shared, isa='PBXBuildFile', fileRef=uid(team_shared))
objects[uid('sources')]['files'] = list(dict.fromkeys(objects[uid('sources')]['files']+[team_build]))
add_to_group(uid('appgroup'), [uid(team_shared)])
cli_shared = 'GrokBot/Core/CLIProtocol.swift'
reference(cli_shared)
cli_build = add('build'+cli_shared, isa='PBXBuildFile', fileRef=uid(cli_shared))
objects[uid('sources')]['files'] = list(dict.fromkeys(objects[uid('sources')]['files']+[cli_build]))
add_to_group(uid('appgroup'), [uid(cli_shared)])
glass_build = add('build'+glass, isa='PBXBuildFile', fileRef=uid(glass))
objects[uid('sources')]['files'] = list(dict.fromkeys(objects[uid('sources')]['files']+[glass_build]))
add_to_group(uid('appgroup'), [uid(glass)])
ios_entitlements = 'GrokBot/Resources/GrokBot.entitlements'
reference(ios_entitlements, 'text.plist.entitlements')
add_to_group(uid('appgroup'), [uid(ios_entitlements)])
for configuration in ('Debug','Release'):
    objects[uid('app'+configuration)]['buildSettings']['CODE_SIGN_ENTITLEMENTS'] = ios_entitlements
    objects[uid('app'+configuration)]['buildSettings']['MARKETING_VERSION'] = '0.7.4'
    objects[uid('app'+configuration)]['buildSettings']['CURRENT_PROJECT_VERSION'] = '12'

mac_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'GrokBotMac').rglob('*.swift'))
shared = ['GrokBot/Remote/RemoteController.swift','GrokBot/App/AppModel.swift','GrokBot/Core/Models.swift','GrokBot/Core/WorkspaceStore.swift','GrokBot/Security/KeychainSecretStore.swift','GrokBot/Core/CLIProtocol.swift',team_shared,glass,avatar]+remote_shared
tests = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'GrokBotTests').glob('*.swift'))
add_to_group(uid('testgroup'), [reference(p) for p in tests])
for path in tests:
    if path.startswith('GrokBotTests/Mac') or path.endswith('LocalCLIRunnerTests.swift'): continue
    build = add('build'+path, isa='PBXBuildFile', fileRef=reference(path))
    objects[uid('testsources')]['files'] = list(dict.fromkeys(objects[uid('testsources')]['files']+[build]))
for path in mac_sources: reference(path)
for path, kind in [('GrokBotMac/Resources/Info.plist','text.plist.xml'),('GrokBotMac/Resources/GrokBotMac.entitlements','text.plist.entitlements'),('GrokBotMac/Resources/AppIcon.icns','image.icns')]: reference(path,kind)
mac_id=uid('mac-target'); test_id=uid('mac-test-target')
app_product=add('mac-product',isa='PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path='OpenGrokBot.app',sourceTree='BUILT_PRODUCTS_DIR')
test_product=add('mac-test-product',isa='PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex='0',path='GrokBotMacTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
add_to_group(uid('products'),[app_product,test_product])
mac_group=add('mac-group',isa='PBXGroup',children=[uid(p) for p in mac_sources]+[uid('GrokBotMac/Resources/'+p) for p in ['Info.plist','GrokBotMac.entitlements','AppIcon.icns']],name='GrokBotMac',sourceTree='<group>')
add_to_group(uid('main'),[mac_group])
base={'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SUPPORTED_PLATFORMS':'macosx','SWIFT_VERSION':'6.0','CODE_SIGN_STYLE':'Automatic','SWIFT_STRICT_CONCURRENCY':'complete','COMBINE_HIDPI_IMAGES':'YES'}
app_configs=configs('mac-app',base|{'PRODUCT_BUNDLE_IDENTIFIER':'org.opengrokbot.mac','PRODUCT_NAME':'OpenGrokBot','PRODUCT_MODULE_NAME':'GrokBotMac','INFOPLIST_FILE':'GrokBotMac/Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CURRENT_PROJECT_VERSION':'12','MARKETING_VERSION':'0.7.4','CODE_SIGN_ENTITLEMENTS':'GrokBotMac/Resources/GrokBotMac.entitlements','ENABLE_HARDENED_RUNTIME':'YES','ENABLE_APP_SANDBOX':'NO','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks']})
test_configs=configs('mac-test',base|{'PRODUCT_BUNDLE_IDENTIFIER':'org.opengrokbot.mac.tests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/OpenGrokBot.app/Contents/MacOS/OpenGrokBot','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks','@loader_path/../Frameworks']})
proxy=add('mac-proxy',isa='PBXContainerItemProxy',containerPortal=project['rootObject'],proxyType='1',remoteGlobalIDString=mac_id,remoteInfo='GrokBotMac')
dep=add('mac-dependency',isa='PBXTargetDependency',target=mac_id,targetProxy=proxy)
objects[mac_id]={'isa':'PBXNativeTarget','buildConfigurationList':app_configs,'buildPhases':[phase('mac-sources',mac_sources+shared,'PBXSourcesBuildPhase'),phase('mac-frameworks',[],'PBXFrameworksBuildPhase'),phase('mac-resources',['GrokBotMac/Resources/AppIcon.icns','GrokBot/Resources/PrivacyInfo.xcprivacy'],'PBXResourcesBuildPhase')],'buildRules':[],'dependencies':[],'name':'GrokBotMac','productName':'OpenGrokBot','productReference':app_product,'productType':'com.apple.product-type.application'}
objects[test_id]={'isa':'PBXNativeTarget','buildConfigurationList':test_configs,'buildPhases':[phase('mac-test-sources',tests,'PBXSourcesBuildPhase'),phase('mac-test-frameworks',[],'PBXFrameworksBuildPhase')],'buildRules':[],'dependencies':[dep],'name':'GrokBotMacTests','productName':'GrokBotMacTests','productReference':test_product,'productType':'com.apple.product-type.bundle.unit-test'}
ui_id = uid('mac-ui-target')
ui_path = 'GrokBotMacUITests/MacUITests.swift'
reference(ui_path)
ui_fixture = 'GrokBotMacUITests/Fixtures/codex-fixture.sh'
reference(ui_fixture, 'text.script.sh')
ui_product = add('mac-ui-product',isa='PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex='0',path='GrokBotMacUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
add_to_group(uid('products'),[ui_product])
ui_group = add('mac-ui-group',isa='PBXGroup',children=[uid(ui_path),uid(ui_fixture)],name='GrokBotMacUITests',sourceTree='<group>')
add_to_group(uid('main'),[ui_group])
ui_configs = configs('mac-ui',base|{'PRODUCT_BUNDLE_IDENTIFIER':'org.opengrokbot.mac.uitests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'GrokBotMac'})
objects[ui_id]={'isa':'PBXNativeTarget','buildConfigurationList':ui_configs,'buildPhases':[phase('mac-ui-sources',[ui_path],'PBXSourcesBuildPhase'),phase('mac-ui-frameworks',[],'PBXFrameworksBuildPhase'),phase('mac-ui-resources',[ui_fixture],'PBXResourcesBuildPhase')],'buildRules':[],'dependencies':[dep],'name':'GrokBotMacUITests','productName':'GrokBotMacUITests','productReference':ui_product,'productType':'com.apple.product-type.bundle.ui-testing'}
# Package a native stdio MCP helper; no shell or extra runtime is required on macOS.
helper_id = uid('composio-helper-target')
helper_path = 'ComposioBridge/main.swift'
helper_product = add('composio-helper-product', isa='PBXFileReference', explicitFileType='compiled.mach-o.executable', includeInIndex='0', path='ComposioBridge', sourceTree='BUILT_PRODUCTS_DIR')
add_to_group(uid('products'), [helper_product])
helper_group = add('composio-helper-group',isa='PBXGroup',children=[reference(helper_path)],name='ComposioBridge',sourceTree='<group>')
add_to_group(uid('main'),[helper_group])
helper_configs = configs('composio-helper',base|{'PRODUCT_NAME':'ComposioBridge','PRODUCT_BUNDLE_IDENTIFIER':'org.opengrokbot.composiobridge','ENABLE_HARDENED_RUNTIME':'YES','SKIP_INSTALL':'YES'})
objects[helper_id] = {'isa':'PBXNativeTarget','buildConfigurationList':helper_configs,'buildPhases':[phase('helper-sources',[helper_path],'PBXSourcesBuildPhase'),phase('helper-frameworks',[],'PBXFrameworksBuildPhase')],'buildRules':[],'dependencies':[],'name':'ComposioBridge','productName':'ComposioBridge','productReference':helper_product,'productType':'com.apple.product-type.tool'}
helper_proxy = add('helper-proxy',isa='PBXContainerItemProxy',containerPortal=project['rootObject'],proxyType='1',remoteGlobalIDString=helper_id,remoteInfo='ComposioBridge')
helper_dep = add('helper-dep',isa='PBXTargetDependency',target=helper_id,targetProxy=helper_proxy)
helper_build = add('helper-copy-build',isa='PBXBuildFile',fileRef=helper_product,settings={'ATTRIBUTES':['CodeSignOnCopy']})
helper_copy = add('helper-copy-phase',isa='PBXCopyFilesBuildPhase',buildActionMask='2147483647',dstPath='$(CONTENTS_FOLDER_PATH)/Helpers',dstSubfolderSpec='16',files=[helper_build],runOnlyForDeploymentPostprocessing='0')
objects[mac_id]['dependencies'].append(helper_dep)
objects[mac_id]['buildPhases'].append(helper_copy)
objects[project['rootObject']]['targets']=list(dict.fromkeys(objects[project['rootObject']]['targets']+[mac_id,test_id,ui_id,helper_id]))

def encode(value,indent=0):
    if isinstance(value,dict): return '{\n'+''.join('\t'*(indent+1)+json.dumps(k)+' = '+encode(v,indent+1)+';\n' for k,v in value.items())+'\t'*indent+'}'
    if isinstance(value,list): return '(\n'+''.join('\t'*(indent+1)+encode(v,indent+1)+',\n' for v in value)+'\t'*indent+')'
    return json.dumps(str(value))
# Prune removed Swift files and their stale group/build references.
stale = {key for key, value in objects.items() if value.get('isa') == 'PBXFileReference' and str(value.get('path','')).endswith('.swift') and not (ROOT/value['path']).exists()}
stale |= {key for key,value in objects.items() if value.get('isa') == 'PBXBuildFile' and value.get('fileRef') in stale}
for key in stale: objects.pop(key,None)
for value in objects.values():
    for field in ('children','files'):
        if field in value: value[field] = [key for key in value[field] if key not in stale]
PROJECT.write_text('// !$*UTF8*$!\n'+encode(project)+'\n')
scheme=(ROOT/'GrokBot.xcodeproj/xcshareddata/xcschemes/GrokBot.xcscheme').read_text()
scheme=scheme.replace(uid('app'),mac_id).replace(uid('test'),test_id).replace('BuildableName="GrokBot.app"','BuildableName="OpenGrokBot.app"').replace('BlueprintName="GrokBot"','BlueprintName="GrokBotMac"').replace('BuildableName="GrokBotTests.xctest"','BuildableName="GrokBotMacTests.xctest"').replace('BlueprintName="GrokBotTests"','BlueprintName="GrokBotMacTests"')
scheme = scheme.replace('</Testables>', f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_id}" BuildableName="GrokBotMacUITests.xctest" BlueprintName="GrokBotMacUITests" ReferencedContainer="container:GrokBot.xcodeproj"/></TestableReference></Testables>')
(ROOT/'GrokBot.xcodeproj/xcshareddata/xcschemes/GrokBotMac.xcscheme').write_text(scheme)
print(f'Updated project with {len(mac_sources)} macOS sources and {len(shared)} shared sources.')
