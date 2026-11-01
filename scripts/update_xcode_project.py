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

# Add the shared glass source to the iOS target and source group.
glass = 'GrokBot/Design/GlassChrome.swift'
reference(glass)
glass_build = add('build'+glass, isa='PBXBuildFile', fileRef=uid(glass))
objects[uid('sources')]['files'] = list(dict.fromkeys(objects[uid('sources')]['files']+[glass_build]))
add_to_group(uid('appgroup'), [uid(glass)])

mac_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'GrokBotMac').rglob('*.swift'))
shared = ['GrokBot/App/AppModel.swift','GrokBot/Core/Models.swift','GrokBot/Core/WorkspaceStore.swift','GrokBot/Security/KeychainSecretStore.swift',glass]
tests = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'GrokBotTests').glob('*.swift'))
for path in mac_sources: reference(path)
for path, kind in [('GrokBotMac/Resources/Info.plist','text.plist.xml'),('GrokBotMac/Resources/GrokBotMac.entitlements','text.plist.entitlements'),('GrokBotMac/Resources/AppIcon.icns','image.icns')]: reference(path,kind)
mac_id=uid('mac-target'); test_id=uid('mac-test-target')
app_product=add('mac-product',isa='PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path='OpenGrokBot.app',sourceTree='BUILT_PRODUCTS_DIR')
test_product=add('mac-test-product',isa='PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex='0',path='GrokBotMacTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
add_to_group(uid('products'),[app_product,test_product])
mac_group=add('mac-group',isa='PBXGroup',children=[uid(p) for p in mac_sources]+[uid('GrokBotMac/Resources/'+p) for p in ['Info.plist','GrokBotMac.entitlements','AppIcon.icns']],name='GrokBotMac',sourceTree='<group>')
add_to_group(uid('main'),[mac_group])
base={'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SUPPORTED_PLATFORMS':'macosx','SWIFT_VERSION':'6.0','CODE_SIGN_STYLE':'Automatic','SWIFT_STRICT_CONCURRENCY':'complete','COMBINE_HIDPI_IMAGES':'YES'}
app_configs=configs('mac-app',base|{'PRODUCT_BUNDLE_IDENTIFIER':'org.opengrokbot.mac','PRODUCT_NAME':'OpenGrokBot','PRODUCT_MODULE_NAME':'GrokBotMac','INFOPLIST_FILE':'GrokBotMac/Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CURRENT_PROJECT_VERSION':'2','MARKETING_VERSION':'0.2.0','CODE_SIGN_ENTITLEMENTS':'GrokBotMac/Resources/GrokBotMac.entitlements','ENABLE_HARDENED_RUNTIME':'YES','ENABLE_APP_SANDBOX':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks']})
test_configs=configs('mac-test',base|{'PRODUCT_BUNDLE_IDENTIFIER':'org.opengrokbot.mac.tests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/OpenGrokBot.app/Contents/MacOS/OpenGrokBot','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks','@loader_path/../Frameworks']})
proxy=add('mac-proxy',isa='PBXContainerItemProxy',containerPortal=project['rootObject'],proxyType='1',remoteGlobalIDString=mac_id,remoteInfo='GrokBotMac')
dep=add('mac-dependency',isa='PBXTargetDependency',target=mac_id,targetProxy=proxy)
objects[mac_id]={'isa':'PBXNativeTarget','buildConfigurationList':app_configs,'buildPhases':[phase('mac-sources',mac_sources+shared,'PBXSourcesBuildPhase'),phase('mac-frameworks',[],'PBXFrameworksBuildPhase'),phase('mac-resources',['GrokBotMac/Resources/AppIcon.icns','GrokBot/Resources/PrivacyInfo.xcprivacy'],'PBXResourcesBuildPhase')],'buildRules':[],'dependencies':[],'name':'GrokBotMac','productName':'OpenGrokBot','productReference':app_product,'productType':'com.apple.product-type.application'}
objects[test_id]={'isa':'PBXNativeTarget','buildConfigurationList':test_configs,'buildPhases':[phase('mac-test-sources',tests,'PBXSourcesBuildPhase'),phase('mac-test-frameworks',[],'PBXFrameworksBuildPhase')],'buildRules':[],'dependencies':[dep],'name':'GrokBotMacTests','productName':'GrokBotMacTests','productReference':test_product,'productType':'com.apple.product-type.bundle.unit-test'}
objects[project['rootObject']]['targets']=list(dict.fromkeys(objects[project['rootObject']]['targets']+[mac_id,test_id]))

def encode(value,indent=0):
    if isinstance(value,dict): return '{\n'+''.join('\t'*(indent+1)+json.dumps(k)+' = '+encode(v,indent+1)+';\n' for k,v in value.items())+'\t'*indent+'}'
    if isinstance(value,list): return '(\n'+''.join('\t'*(indent+1)+encode(v,indent+1)+',\n' for v in value)+'\t'*indent+')'
    return json.dumps(str(value))
PROJECT.write_text('// !$*UTF8*$!\n'+encode(project)+'\n')
scheme=(ROOT/'GrokBot.xcodeproj/xcshareddata/xcschemes/GrokBot.xcscheme').read_text()
scheme=scheme.replace(uid('app'),mac_id).replace(uid('test'),test_id).replace('BuildableName="GrokBot.app"','BuildableName="OpenGrokBot.app"').replace('BlueprintName="GrokBot"','BlueprintName="GrokBotMac"').replace('BuildableName="GrokBotTests.xctest"','BuildableName="GrokBotMacTests.xctest"').replace('BlueprintName="GrokBotTests"','BlueprintName="GrokBotMacTests"')
(ROOT/'GrokBot.xcodeproj/xcshareddata/xcschemes/GrokBotMac.xcscheme').write_text(scheme)
print(f'Updated project with {len(mac_sources)} macOS sources and {len(shared)} shared sources.')
