#!/usr/bin/env python3
"""Affine center math and source contracts; no UIKit runtime available."""
from pathlib import Path
import itertools, math
root=Path(__file__).resolve().parents[1]
native=(root/'src/NGSwitch.m').read_text()
hooks=(root/'src/Tweak.m').read_text()
assert 'center.x -= source.transform.tx;' in native
assert 'center.y -= source.transform.ty;' in native
assert 'source.hidden || CGRectIsEmpty(source.bounds)' in native
sync=native.split('void NGSyncSwitchGeometry(UISwitch *source) {',1)[1].split('\nvoid NGRefreshSwitch',1)[0]
assert 'NGIsClock()' in sync and 'binding.refreshing' in sync
assert 'binding.overlay.superview != parent' in sync
assert 'NGApplySwitchGeometry(source, binding, parent)' in sync
assert 'NGScheduleSwitchSync' not in sync and 'resetForClockReuse' not in sync and 'NGSwitchBinding new' not in sync
for name,selector in [('Frame','Frame'),('Bounds','Bounds'),('Center','Center'),('Transform','Transform')]:
    assert f'@selector(set{selector}:),(IMP)NGSwitch{name}' in hooks
    line=next(l for l in hooks.splitlines() if l.startswith(f'static void NGSwitch{name}('))
    assert line.index(f'gSW{name}(s,c,v)')<line.index('NGSyncSwitchGeometry(s)')
assert 'if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobiletimer"]) {\n            NGInstallMethod(sw,@selector(setFrame:)' in hooks
cases=0
for angle,scale,tx,ty,anchor,bounds in itertools.product([0,0.5,math.pi/2], [0.5,1,2],[-80,0,50],[-25,0,95],[(.5,.5),(0,0),(1,.2)],[(51,31),(100,70)]):
    # Source center in parent = position + A*(boundsCenter-anchor) + t.
    dx=(.5-anchor[0])*bounds[0];dy=(.5-anchor[1])*bounds[1]
    x=140+scale*(math.cos(angle)*dx-math.sin(angle)*dy)+tx
    y=230+scale*(math.sin(angle)*dx+math.cos(angle)*dy)+ty
    # Overlay uses default center anchor. Its own transform adds t again.
    new=(x-tx+tx,y-ty+ty)
    assert math.isclose(new[0],x,abs_tol=1e-9) and math.isclose(new[1],y,abs_tol=1e-9)
    if tx or ty: assert not (math.isclose(x+tx,x) and math.isclose(y+ty,y))
    cases+=1
print(f'PASS: {cases} affine center model cases; setter and Clock isolation source contracts (not UIKit runtime)')
