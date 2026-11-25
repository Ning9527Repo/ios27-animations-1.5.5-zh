#!/usr/bin/env python3
"""Package identity is independent of the saved-preferences namespace."""
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
NEW = 'com.ning.ios2627anims'
OLD = 'com.bazik1337.ios2627anims'
control = dict(line.split(': ', 1) for line in
               (ROOT / 'iOS27Animations/control').read_text().splitlines() if ': ' in line)
assert control['Package'] == NEW
assert control['Name'] == 'iOS 27 动画'
assert control['Author'] == control['Maintainer'] == 'Ning'
assert control['Version'] == '0.1' and control['Architecture'] == 'iphoneos-arm64e'
assert 'Icon' not in control
for field in ('Conflicts', 'Replaces'):
    entries = [x.strip() for x in control[field].split(',')]
    assert OLD in entries and NEW not in entries, (field, entries)
expected = f"{control['Package']}_{control['Version']}_{control['Architecture']}.deb"
assert expected == 'com.ning.ios2627anims_0.1_iphoneos-arm64e.deb'
# Do not blindly replace the legacy preferences namespace: existing settings
# must remain readable by the unchanged Settings and runtime implementation.
res = ROOT / 'iOS27Animations/Prefs/Resources'
for page in ('Root', 'AppAnimations', 'NotificationCenter', 'Advanced'):
    rows = plistlib.loads((res / (page + '.plist')).read_bytes())['items']
    for row in rows:
        if 'key' in row:
            assert row['defaults'] == OLD
            assert row['PostNotification'] == OLD + '/changed'
header = (ROOT / 'shared/LiquidSwitchConfiguration.h').read_text()
assert f'CG27LSDomain = @"{OLD}";' in header
assert f'CG27LSChanged = @"{OLD}/changed";' in header
workflow = (ROOT / '.github/workflows/build-roothide.yml').read_text()
assert f'usr/share/doc/{OLD}/' not in workflow
assert workflow.count(f'usr/share/doc/{NEW}/Theseus') == 4
assert 'python3 tests/check-package-identity.py' in workflow
assert not re.search(r'^\s+(push|pull_request|schedule):', workflow, re.M)
print('PASS package identity: Sileo name iOS 27 动画; Author/Maintainer Ning; ' + expected)
print('PASS legacy package Conflicts/Replaces; saved preferences and notification namespace retained')
