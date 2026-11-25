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
clean_tail=[]
for row in fixture['root_tail']:
    if row.get('label')=='Author': break
    clean_tail.append({k:v for k,v in row.items() if k!='iconSymbol'})
assert main[7:]==clean_tail, 'homepage changed beyond removed author/footer/icons'
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
controller_path='iOS27Animations/Prefs/CG27RootListController.m'
for path,digest in fixture['immutable'].items():
    if path != controller_path:
        assert hashlib.sha256((root/path).read_bytes()).hexdigest()==digest, 'unrelated code changed: '+path
baseline=json.loads((root/'tests/fixtures/settings-controller-before-switch-fix.json').read_text())
source=(root/controller_path).read_text()
starts=list(re.finditer(r'^[-+] \([^\n]+\).*?\{',source,re.M)); methods={}
for i,m in enumerate(starts):
    end=starts[i+1].start() if i+1<len(starts) else len(source)
    text=source[m.start():end].split('\n@end',1)[0].strip()
    cls=re.findall(r'^@implementation (\w+)',source[:m.start()],re.M)[-1]
    key=cls+' '+m.group().rsplit('{',1)[0].strip()
    assert key not in methods,key
    methods[key]=hashlib.sha256(text.encode()).hexdigest()
removed={
    'CG27RootListController - (void)'+name for name in
    ('dealloc','viewDidAppear:(BOOL)animated','showPrompt','open:(NSString *)url',
     'openTelegram','openChannel','openGitHub')
}
appearance_changed={
    'CG27PageController - (NSArray *)specifiers',
    'CG27PageController - (void)viewDidLoad',
    'CG27PageController - (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath',
    'CG27RootListController - (void)viewDidLoad',
}
added={'CG27PageController - (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath'}
assert set(methods)==(set(baseline['methods'])-removed)|set(baseline['added_methods'])|added
for key,digest in baseline['methods'].items():
    if key not in set(baseline['changed_methods'])|appearance_changed|removed:
        assert methods[key]==digest,key
print('PASS: three submenus, one card per page, all 10 controls/languages and animation engine unchanged; approved promotion/icon removal and appearance changes only (static only)')
