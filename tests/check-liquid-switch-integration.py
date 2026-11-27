#!/usr/bin/env python3
"""Static contract: Theseus switch source is part of the existing animation tweak."""
import hashlib,json,pathlib,plistlib,re
root=pathlib.Path(__file__).resolve().parents[1]
feature=root/'iOS27Animations/SwitchFeature'; vendor=feature/'Vendor'
manifest=json.loads((vendor/'manifest.json').read_text()); patches=json.loads((vendor/'local-patches.json').read_text())
assert len(manifest)==35
for rel,upstream in manifest.items():
    path=root/'iOS27Animations/SwitchFeature'/rel
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest==(patches.get(rel,{}).get('patched_sha256') or upstream),(rel,digest)
mk=(root/'iOS27Animations/Makefile').read_text()
assert 'TWEAK_NAME = iOS2627Anims' in mk
for f in ('src/NGSwitch.m','src/NGResources.m','src/NGSwitchPreferences.m','src/Tweak.m','src/TheseusBridge.swift','src/TheseusBundle.swift'):
    assert f in mk
assert 'find $(SWITCH_DIR)/Vendor/Theseus/Sources/Theseus' in mk
assert 'iOS2627Anims-Bridging-Header.h' in mk or (root/'iOS27Animations/iOS2627Anims-Bridging-Header.h').is_file()
hooks=(feature/'src/Tweak.m').read_text()
filter_text=(root/'iOS27Animations/iOS2627Anims.plist').read_text()
assert set(re.findall(r'"(com\.apple\.[^"]+)"',filter_text))=={'com.apple.springboard','com.apple.UIKit','com.apple.Preferences'}
switch_ctor=hooks[hooks.index('__attribute__((constructor)) static void NGInitialize(void)'):]
assert 'com.apple.Preferences' not in switch_ctor
assert 'com.bazik1337.ios2627anims.prefs' in switch_ctor
keyboard=(root/'iOS27Animations/KeyboardGlass/KeyboardBackground.m').read_text()
keyboard_ctor=keyboard[keyboard.index('__attribute__((constructor)) static void NGInstall(void)'):]
assert 'com.apple.Preferences' not in keyboard_ctor
main=(root/'iOS27Animations/Tweak.x').read_text()
assert '%ctor {\n    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;' in main
hooks=(feature/'src/Tweak.m').read_text(); bridge=(feature/'src/Bridge.h').read_text(); sw=(feature/'src/NGSwitch.m').read_text()
assert 'LiquidSwitchEnabled' in hooks and 'NGSwitchFeatureEnabled' in bridge
assert 'if (!NGSwitchFeatureEnabled())' in hooks and 'NGRemoveAllSwitches' in hooks
assert 'if (!NGSwitchFeatureEnabled()) { NGRemoveSwitch(source); return; }' in sw
assert 'iOS2627Anims.dylib' in (feature/'src/NGResources.m').read_text()
assert 'Library/Application Support/iOS27Animations/TheseusSwitchResources.bundle' in (feature/'src/NGResources.m').read_text()
root_plist=plistlib.loads((root/'iOS27Animations/Prefs/Resources/Root.plist').read_bytes())
rows=root_plist['items']; switch=[x for x in rows if x.get('key')=='LiquidSwitchEnabled']
assert len(switch)==1 and switch[0]['cell']=='PSSwitchCell' and switch[0]['default'] is False
assert switch[0]['defaults']=='com.bazik1337.ios2627anims' and switch[0]['PostNotification']=='com.bazik1337.ios2627anims/changed'
text=(root/'iOS27Animations/Prefs/Resources/zh-Hans.lproj/Root.strings').read_text()
assert '"Liquid switch" =' in text
wf=(root/'.github/workflows/build-roothide.yml').read_text()
assert 'prepare-switch-resources.py' in wf and 'SwitchFeature/LICENSE-Theseus' in wf
assert 'TheseusSwitch.dylib' not in mk+wf
assert 'KeyboardGlass/KeyboardBackground.m' in mk
assert (root/'iOS27Animations/layout/Library/libSandy/KeyboardGlass_ReadConfig.plist').is_file()
config=(root/'shared/LiquidSwitchConfiguration.h').read_text()
reader=(feature/'src/NGSwitchPreferences.m').read_text()
assert 'CFPreferencesCopyAppValue' not in hooks+reader
assert 'if (!NGLoadSwitchFeaturePreference(&enabled)) return;' in hooks
assert 'if (!gNGHasValidSwitchConfiguration) NGRecoverSwitchConfiguration();' in hooks
assert 'libSandy_applyProfile' in reader
assert 'com.opa334.libsandy' in (root/'iOS27Animations/control').read_text()
import os
profile_prefix = '/var/mobile' if os.environ.get('PACKAGE_SCHEME') == 'rootless' else '/rootfs/var/mobile'
profile=plistlib.loads((root/'iOS27Animations/layout/Library/libSandy/iOS27Animations_SwitchReadConfig.plist').read_bytes())
assert profile=={'AllowedProcesses':['*'],'Extensions':[{'type':'file','extension_class':'com.apple.app-sandbox.read','path':profile_prefix+'/Library/Accessibility/iOS27Animations-switch.plist'}]}
kgread=plistlib.loads((root/'iOS27Animations/layout/Library/libSandy/KeyboardGlass_ReadConfig.plist').read_bytes())
assert kgread=={'AllowedProcesses':['*'],'Extensions':[{'type':'file','extension_class':'com.apple.app-sandbox.read','path':profile_prefix+'/Library/Accessibility/KeyboardGlass-preferences.plist'}]}
kgprefs=(root/'iOS27Animations/Prefs/KeyboardGlassController.m').read_text()
assert 'NGPublishGlobalSnapshot(&publishError)' in kgprefs
assert 'CG27LSSavedValueFromImage' in config and 'CG27LSPublishValue' in config
assert 'check-switch-configuration.py' in wf
print('PASS: one main tweak; shared validated snapshot, exact read-only profile, saved-value migration, bounded startup recovery; full vendored Swift/Metal retained')
