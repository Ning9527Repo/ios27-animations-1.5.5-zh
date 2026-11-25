#!/usr/bin/env python3
"""Static resource regression; does not claim UIKit device validation."""
import hashlib,json,pathlib,plistlib,re
root=pathlib.Path(__file__).resolve().parents[1]
res=root/'iOS27Animations/Prefs/Resources'
fixture=json.loads((root/'tests/fixtures/settings-before-submenus.json').read_text())
pages={name:plistlib.loads((res/(name+'.plist')).read_bytes()) for name in ('Root','AppAnimations','NotificationCenter','Advanced')}
main=pages['Root']['items']
assert main[:2]==fixture['root_prefix'], 'master enable changed'
assert main[2]==fixture['switch_control']
assert main[7:]==fixture['root_tail'], 'unrelated homepage rows changed'
links=[x for x in main if x.get('cell')=='PSLinkCell']
assert [(x['label'],x['plist']) for x in links]==[('ios27动画','AppAnimations'),('Notification Center','NotificationCenter'),('Advanced','Advanced')]
for link in links:
    assert link['detail']=='CG27PageController' and link['isController'] is True
assert {x['key'] for x in main if 'key' in x}=={'Enabled','LiquidSwitchEnabled'}
expected={'AppAnimations':['AppAnimations','OpenSpeed','CloseSpeed'],'NotificationCenter':['IconFlyIn','ClearSheet'],'Advanced':['Intensity','GestureBounce','FlyStrength','GlobalSlow']}
controls={x['key']:x for page in pages.values() for x in page['items'] if 'key' in x}
assert controls==fixture['controls'], 'preference controls, defaults, domains or ranges changed'
for name,keys in expected.items():
    rows=pages[name]['items']
    assert rows[0]=={'cell':'PSGroupCell'}
    assert sum(x.get('cell')=='PSGroupCell' for x in rows)==1, name+' split into cards'
    assert [x['key'] for x in rows if 'key' in x]==keys
    assert all(x['cell'] in ('PSGroupCell','PSStaticTextCell','PSSwitchCell','PSSliderCell') for x in rows)
    for index,row in enumerate(rows):
        if row.get('cell')=='PSSliderCell':
            assert rows[index-1]['cell']=='PSStaticTextCell' and rows[index-1]['label'], 'slider label missing'
    for lang in ('en','ru','zh-Hans'):
        strings=res/(lang+'.lproj')/(name+'.strings')
        pairs=re.findall(r'^"([^"\n]+)"\s*=\s*"([^"\n]*)";',strings.read_text(),re.M)
        trans=dict(pairs); assert len(trans)==len(pairs), 'duplicate translation'
        labels={x['label'] for x in rows if x.get('label')}|{pages[name]['title']}
        assert labels<=set(trans), (name,lang,labels-set(trans))
for path,digest in fixture['immutable'].items():
    assert hashlib.sha256((root/path).read_bytes()).hexdigest()==digest, 'unrelated code changed: '+path
print('PASS: three submenu routes, one card per page, all 10 existing controls unchanged; one switch toggle added, three languages, engine/controller byte-identical (static only)')
