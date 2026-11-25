#!/usr/bin/env python3
import pathlib,plistlib,re,hashlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
prefs=root/'iOS27Animations/Prefs'
original=root/'iOS27Animations'
assert 'THEOS_PACKAGE_SCHEME = roothide' in (original/'Makefile').read_text()
assert 'ARCHS = arm64e' in (original/'Makefile').read_text()
assert 'ARCHS = arm64e' in (prefs/'Makefile').read_text()
assert '-F$(THEOS_PROJECT_DIR)/Prefs/linker' in (prefs/'Makefile').read_text()
stub=prefs/'linker/Preferences.framework/Preferences.tbd'
assert 'PSListController._specifiers' in stub.read_text()
assert 'PSTableCell' in stub.read_text()
assert 'PSSpecifier' in stub.read_text()
assert '/System/Library/PrivateFrameworks/Preferences.framework/Preferences' in stub.read_text()
for page in ('Root','AppAnimations','NotificationCenter','Advanced','KeyboardGlass'):
    r=prefs/'Resources'
    data=plistlib.loads((r/(page+'.plist')).read_bytes())
    s=(r/'zh-Hans.lproj'/(page+'.strings')).read_text()
    translations=dict(re.findall(r'^"([^"\n]+)"\s*=\s*"([^"\n]*)";',s,re.M))
    keys={item.get('label') for item in data['items'] if item.get('label')}
    keys.add(data['title'])
    assert not (keys-set(translations)-{'@bazik1337','GitHub'}),keys-set(translations)
    if page=='Root': assert translations.get('Keyboard Glass')=='键盘仿玻璃'
    assert all(translations.values())
    print(page,len(data['items']),len(translations))
for p in root.rglob('*.plist'):
    if p.name in ('iOS2627Anims.plist','iOS27AnimsReborn.plist'):
        assert 'com.apple.springboard' in p.read_text()
        if p.name=='iOS2627Anims.plist': assert 'com.apple.Preferences' in p.read_text()
    else:
        plistlib.loads(p.read_bytes())
entry=plistlib.loads((prefs/'layout/Library/PreferenceLoader/Preferences/iOS2627AnimsPrefs.plist').read_bytes())['entry']
assert entry['label']=='iOS 27 动画' and entry['icon']=='icon.png'
main=plistlib.loads((prefs/'Resources/Root.plist').read_bytes())['items']
links=[x for x in main if x.get('cell')=='PSLinkCell']
assert sum(x.get('label')=='Keyboard Glass' and x.get('plist')=='KeyboardGlass' for x in links)==1
assert not (prefs/'KeyboardGlassEntry.plist').exists()
control=dict(line.split(': ',1) for line in (original/'control').read_text().splitlines() if ': ' in line)
assert control['Version']=='0.3' and control['Architecture']=='iphoneos-arm64e'
assert control['Package']=='com.ning.ios2627anims'
assert control['Name']=='iOS 27 动画' and 'Icon' not in control
assert control['Author']=='Ning' and control['Maintainer']=='Ning'
assert (root/'iOS27Animations/Tweak.x').is_file() and (root/'iOS27Animations/GenieEngine.h').is_file()
assert (root/'iOS27AnimationsReborn/Tweak.x').is_file()
wf=(root/'.github/workflows/build-roothide.yml').read_text()
assert 'workflow_dispatch:' in wf and not re.search(r'^\s+(push|pull_request|schedule):',wf,re.M)
print('PASS complete upstream source and localized resources (static only)')
