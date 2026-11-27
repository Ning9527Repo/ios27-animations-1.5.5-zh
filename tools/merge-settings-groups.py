#!/usr/bin/env python3
import plistlib
import shutil
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'iOS27Animations/Prefs/Resources'
def load(name):
    path = root / f'{name}.plist'
    return path, plistlib.loads(path.read_bytes())
def save(path, data):
    path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=False))

rp, main = load('Root')
rows = main['items']
# Card 1: master enable plus animation settings entry.
# Card 2: the liquid switch remains independent.
# Card 3: keyboard-glass master switch and its settings entry.
enabled = next(x for x in rows if x.get('key') == 'Enabled')
liquid = next(x for x in rows if x.get('key') == 'LiquidSwitchEnabled')
app = next(x for x in rows if x.get('plist') == 'AppAnimations')
keyboard = next(x for x in rows if x.get('plist') == 'KeyboardGlass')
banner_toggle = {'cell':'PSSwitchCell','label':'启用通知横幅动画','key':'BannerAnimationEnabled',
                 'defaults':'com.ning.ios2627anims','default':False,
                 'PostNotification':'com.ning.ios2627anims/changed'}
banner_link = {'cell':'PSLinkCell','detail':'CG27PageController','isController':True,
               'label':'通知横幅动画','plist':'BannerAnimation'}
kg_toggle = {'cell':'PSSwitchCell','label':'Enabled','key':'KeyboardGlassEnabled',
             'defaults':'com.ning.keyboardglass','default':True,
             'PostNotification':'com.ning.keyboardglass/ReloadPrefs'}
main['items'] = [
    {'cell':'PSGroupCell'}, enabled, app,
    {'cell':'PSGroupCell'}, liquid,
    {'cell':'PSGroupCell'}, banner_toggle, banner_link,
    {'cell':'PSGroupCell'}, kg_toggle, keyboard,
    {'cell':'PSGroupCell'},
    next(x for x in rows if x.get('action') == 'resetSettings'),
    next(x for x in rows if x.get('action') == 'respring'),
]
save(rp, main)

ap, animation = load('AppAnimations')
_, notification = load('NotificationCenter')
_, advanced = load('Advanced')
by_key = {x['key']: x for x in animation['items'] if 'key' in x}
app_controls = [by_key['AppAnimations'],
    {'cell':'PSStaticTextCell','label':'Opening speed'},by_key['OpenSpeed'],
    {'cell':'PSStaticTextCell','label':'Closing speed'},by_key['CloseSpeed']]
controls = [{'cell':'PSGroupCell'}] + app_controls
controls += [{'cell':'PSGroupCell','label':'Notification Center'}]
controls += [x for x in notification['items'] if x.get('cell') != 'PSGroupCell']
controls += [{'cell':'PSGroupCell','label':'Advanced'}]
controls += [x for x in advanced['items'] if x.get('cell') != 'PSGroupCell']
animation['items'] = controls
save(ap, animation)
for lang in ('en.lproj','ru.lproj'):
    shutil.rmtree(root / lang, ignore_errors=True)
print('final root cards and direct Chinese sections merged')
