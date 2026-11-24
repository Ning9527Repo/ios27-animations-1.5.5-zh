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
assert '/System/Library/PrivateFrameworks/Preferences.framework/Preferences' in stub.read_text()
for page in ('Root','Advanced'):
    r=prefs/'Resources'
    data=plistlib.loads((r/(page+'.plist')).read_bytes())
    s=(r/'zh-Hans.lproj'/(page+'.strings')).read_text()
    translations=dict(re.findall(r'^"([^"\n]+)"\s*=\s*"([^"\n]*)";',s,re.M))
    keys={item.get('label') for item in data['items'] if item.get('label')}
    keys.add(data['title'])
    assert not (keys-set(translations)-{'@bazik1337','GitHub'}),keys-set(translations)
    assert all(translations.values())
    print(page,len(data['items']),len(translations))
for p in root.rglob('*.plist'):
    if p.name in ('iOS2627Anims.plist','iOS27AnimsReborn.plist'):
        assert 'com.apple.springboard' in p.read_text()
    else:
        plistlib.loads(p.read_bytes())
entry=plistlib.loads((prefs/'layout/Library/PreferenceLoader/Preferences/iOS2627AnimsPrefs.plist').read_bytes())['entry']
assert entry['label']=='iOS 27 动画' and entry['icon']=='icon.png'
control=dict(line.split(': ',1) for line in (original/'control').read_text().splitlines() if ': ' in line)
assert control['Version']=='1.5.5+ningzh1' and control['Architecture']=='iphoneos-arm64e'
assert control['Author']=='Ning&bazik1337' and control['Maintainer']=='Ning&bazik1337'
assert (root/'iOS27Animations/Tweak.x').is_file() and (root/'iOS27Animations/GenieEngine.h').is_file()
assert (root/'iOS27AnimationsReborn/Tweak.x').is_file()
wf=(root/'.github/workflows/build-roothide.yml').read_text()
assert 'workflow_dispatch:' in wf and not re.search(r'^\s+(push|pull_request|schedule):',wf,re.M)
print('PASS complete upstream source and localized resources (static only)')
