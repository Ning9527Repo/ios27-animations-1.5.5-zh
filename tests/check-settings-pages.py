#!/usr/bin/env python3
"""Static resource regression; does not claim UIKit device validation."""
import hashlib,json,pathlib,plistlib,re
root=pathlib.Path(__file__).resolve().parents[1]
res=root/'iOS27Animations/Prefs/Resources'
fixture=json.loads((root/'tests/fixtures/settings-before-submenus.json').read_text())
pages={name:plistlib.loads((res/(name+'.plist')).read_bytes()) for name in ('Root','AppAnimations','NotificationCenter','Advanced','KeyboardGlass','BannerAnimation')}
main=pages['Root']['items']
assert main[0]=={'cell':'PSGroupCell'}
assert main[1]['key']=='Enabled' and main[2]['plist']=='AppAnimations'
assert main[3]=={'cell':'PSGroupCell'} and main[4]['key']=='LiquidSwitchEnabled'
assert main[5]=={'cell':'PSGroupCell'}
assert main[6]['key']=='BannerAnimationEnabled' and main[6]['default'] is False
assert main[7]=={'cell':'PSLinkCell','detail':'CG27PageController','isController':True,'label':'通知横幅动画','plist':'BannerAnimation'}
assert main[8]=={'cell':'PSGroupCell'}
assert main[9]['key']=='KeyboardGlassEnabled' and main[9]['label']=='Enabled' and main[9]['default'] is True
assert main[10]['cell']=='PSLinkCell' and main[10]['plist']=='KeyboardGlass'
assert main[11:]==[{'cell':'PSGroupCell'}, {'action':'resetSettings','cell':'PSButtonCell','label':'Reset settings'}, {'action':'respring','cell':'PSButtonCell','label':'Respring'}]
links=[x for x in main if x.get('cell')=='PSLinkCell']
assert [(x['label'],x['plist']) for x in links]==[('ios27动画','AppAnimations'),('通知横幅动画','BannerAnimation'),('Keyboard Glass','KeyboardGlass')]
assert [x['key'] for x in pages['BannerAnimation']['items'] if 'key' in x]==['BannerElasticity','BannerTransitionScale','BannerDwellScale']
app_rows=pages['AppAnimations']['items']
assert not any(x.get('cell')=='PSLinkCell' for x in app_rows), 'nested third-level links remain'
assert [x.get('label') for x in app_rows if x.get('cell')=='PSGroupCell']==[None,'Notification Center','Advanced']
assert [x['key'] for x in app_rows if 'key' in x]==['AppAnimations','OpenSpeed','CloseSpeed','IconFlyIn','ClearSheet','Intensity','GestureBounce','FlyStrength','GlobalSlow']
assert {x['key'] for x in main if 'key' in x}=={'Enabled','LiquidSwitchEnabled','BannerAnimationEnabled','KeyboardGlassEnabled'}
assert sum(x.get('cell')=='PSSwitchCell' and x.get('key')=='BannerAnimationEnabled' for x in main)==1
assert (root/'iOS27Animations/Makefile').read_text().count('$(BANNER_DIR)/NB27Banner.m')==1
assert not list((root/'iOS27Animations').glob('**/NB27*.dylib'))
assert not (res/'en.lproj').exists() and not (res/'ru.lproj').exists()
assert sum(x.get('label')=='Keyboard Glass' and x.get('plist')=='KeyboardGlass' for x in links)==1
assert sum(bool(x.get('entry')) for x in main)==0
assert (root/'iOS27Animations/Makefile').read_text().count('KeyboardGlass/KeyboardBackground.m')==1
assert 'KeyboardGlassController.m' in (root/'iOS27Animations/Prefs/Makefile').read_text()
base_header=(root/'iOS27Animations/Prefs/CG27PageController.h').read_text()
kg_header=(root/'iOS27Animations/Prefs/KeyboardGlassPageController.h').read_text()
assert 'readPreferenceValue:' not in base_header and 'readPreferenceValue:' in kg_header
assert '@property(nonatomic, strong) NSMutableArray *ngSpecifiers;' in kg_header
kgcontroller=(root/'iOS27Animations/Prefs/KeyboardGlassController.m').read_text()
assert '- (void)setSpecifiers:(NSMutableArray *)rows' in kgcontroller
assert 'mutableCopy];' in kgcontroller
assert sum(x.get('cell')=='PSSwitchCell' for x in pages['KeyboardGlass']['items'])==3
assert [x['key'] for x in main if x.get('defaults')=='com.ning.keyboardglass']==['KeyboardGlassEnabled']
assert sum(x.get('cell')=='PSSliderCell' for x in pages['KeyboardGlass']['items'])==17
assert sum(x.get('cell')=='PSGroupCell' for x in pages['KeyboardGlass']['items'])==10
assert all(x.get('cellClass')=='NGGlassSliderCell' and x.get('height')==92 for x in pages['KeyboardGlass']['items'] if x.get('cell')=='PSSliderCell')
for lang in ('zh-Hans',):
    pairs=re.findall(r'^"([^"\n]+)"\s*=\s*"([^"\n]*)";', (res/(lang+'.lproj')/'KeyboardGlass.strings').read_text(),re.M)
    trans=dict(pairs)
    assert len(trans)==len(pairs)
    labels={x['label'] for x in pages['KeyboardGlass']['items'] if x.get('label')}|{pages['KeyboardGlass']['title']}
    assert labels<=set(trans),(lang,labels-set(trans))
kgsource=(root/'iOS27Animations/KeyboardGlass/KeyboardBackground.m').read_text()
mk=(root/'iOS27Animations/Makefile').read_text()
assert 'KeyboardGlass/KeyboardBackground.m' in mk
assert 'NGInstallCandidateHooks();' in kgsource and 'NGInstallBackdropHook();' in kgsource
assert 'com.apple.Preferences' not in kgsource[kgsource.index('__attribute__((constructor)) static void NGInstall(void)'):]
filter_text=(root/'iOS27Animations/iOS2627Anims.plist').read_text()
assert 'com.apple.Preferences' in filter_text
assert '[NSBundle bundleForClass:CG27KeyboardGlassController.class]' in (root/'iOS27Animations/Prefs/KeyboardGlassController.m').read_text()
assert 'loadSpecifiersFromPlistName:@"KeyboardGlass"' in (root/'iOS27Animations/Prefs/KeyboardGlassController.m').read_text()
assert not (root/'iOS27Animations/Prefs/Resources/KeyboardGlassEntry.plist').exists()
assert not list((root/'iOS27Animations/Prefs').glob('KeyboardGlass*.dylib'))

expected={'AppAnimations':['AppAnimations','OpenSpeed','CloseSpeed','IconFlyIn','ClearSheet','Intensity','GestureBounce','FlyStrength','GlobalSlow']}
controls={x['key']:x for name,page in pages.items() if name not in ('KeyboardGlass','BannerAnimation') for x in page['items'] if 'key' in x and x['key'] not in ('KeyboardGlassEnabled','BannerAnimationEnabled')}
legacy_controls={key:dict(value) for key,value in fixture['controls'].items()}
for value in legacy_controls.values():
    value['defaults']='com.ning.ios2627anims'
    value['PostNotification']='com.ning.ios2627anims/changed'
assert controls==legacy_controls, 'preference controls, defaults, domains or ranges changed'
assert {x['key'] for x in pages['BannerAnimation']['items'] if 'key' in x}=={'BannerElasticity','BannerTransitionScale','BannerDwellScale'}
for name,keys in expected.items():
    rows=pages[name]['items']
    assert rows[0]=={'cell':'PSGroupCell'}
    if name=='AppAnimations':
        assert [x.get('label') for x in rows if x.get('cell')=='PSGroupCell']==[None,'Notification Center','Advanced']
    else:
        assert sum(x.get('cell')=='PSGroupCell' for x in rows)==1, name+' split into cards'
    assert [x['key'] for x in rows if 'key' in x]==keys
    assert all(x['cell'] in ('PSGroupCell','PSStaticTextCell','PSSwitchCell','PSSliderCell') for x in rows)
    for index,row in enumerate(rows):
        if row.get('cell')=='PSSliderCell':
            assert rows[index-1]['cell']=='PSStaticTextCell' and rows[index-1]['label'], 'slider label missing'
    for lang in ('zh-Hans',):
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
