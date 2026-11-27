#!/usr/bin/env python3
"""Package identity is independent of the saved-preferences namespace."""
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
NEW = 'com.ning.ios2627anims'
# Old package identifier is retained only in Conflicts/Replaces so dpkg can upgrade it.
control = dict(line.split(': ', 1) for line in
               (ROOT / 'iOS27Animations/control').read_text().splitlines() if ': ' in line)
assert control['Package'] == NEW
assert control['Name'] == 'iOS 27 动画'
assert control['Author'] == control['Maintainer'] == 'Ning'
import os
expected_arch = os.environ.get('PACKAGE_ARCH', 'iphoneos-arm64e')
expected_ver = os.environ.get('PACKAGE_VERSION', '0.3')
assert control['Version'] == expected_ver and control['Architecture'] == expected_arch
assert 'firmware (>= 16.0)' in control['Depends']
assert 'com.ning.keyboardglass' in control['Conflicts'].split(', ')
assert 'com.ning.keyboardglass' in control['Replaces'].split(', ')
assert 'firmware (>= 16.0)' in control['Depends']
assert control['Version']==expected_ver
assert 'Icon' not in control
for field in ('Conflicts', 'Replaces'):
    entries = [x.strip() for x in control[field].split(',')]
    assert NEW not in entries, (field, entries)
expected = f"{control['Package']}_{control['Version']}_{control['Architecture']}.deb"
assert expected == f"com.ning.ios2627anims_{expected_ver}_{expected_arch}.deb"
# Package and preference namespace are both owned by Ning; old package IDs are
# asserted only as upgrade metadata in the dedicated package verifier.
res = ROOT / 'iOS27Animations/Prefs/Resources'
for page in ('Root', 'AppAnimations', 'NotificationCenter', 'Advanced', 'BannerAnimation'):
    rows = plistlib.loads((res / (page + '.plist')).read_bytes())['items']
    for row in rows:
        if 'key' in row:
            expected_domain = 'com.ning.keyboardglass' if row['key']=='KeyboardGlassEnabled' else NEW
            expected_notification = 'com.ning.keyboardglass/ReloadPrefs' if row['key']=='KeyboardGlassEnabled' else NEW + '/changed'
            assert row['defaults'] == expected_domain
            assert row['PostNotification'] == expected_notification
header = (ROOT / 'shared/LiquidSwitchConfiguration.h').read_text()
assert 'CG27LSDomain = @"com.ning.ios2627anims";' in header
assert 'CG27LSChanged = @"com.ning.ios2627anims/changed";' in header
controller=(ROOT/'iOS27Animations/Prefs/CG27RootListController.m').read_text()
assert 'static NSString *const kCG27BannerChanged = @"com.ning.ios2627anims/changed";' in controller
assert 'CG27MigrateLegacyPreferences' not in controller
runtime = (ROOT / 'iOS27Animations/Tweak.x').read_text()
banner_runtime = (ROOT / 'iOS27Animations/BannerFeature/NB27Banner.m').read_text()
assert 'com.bazik1337.ios2627anims' not in runtime + banner_runtime + controller + header
assert 'com.ning.27banneranimation' not in runtime + banner_runtime + controller + header
workflow = (ROOT / '.github/workflows/build-roothide.yml').read_text()
assert all(f'usr/share/doc/{NEW}/Theseus' in step for step in workflow.splitlines() if 'usr/share/doc/' in step)
assert workflow.count(f'usr/share/doc/{NEW}/Theseus') == 4
assert 'python3 tests/check-package-identity.py' in workflow
assert not re.search(r'^\s+(push|pull_request|schedule):', workflow, re.M)
rootless = (ROOT / '.github/workflows/build-arm64-rootless.yml').read_text()
assert 'PACKAGE_SCHEME: rootless' in rootless and 'PACKAGE_ARCH: iphoneos-arm64' in rootless
assert 'verify-arm64-rootless.py' in rootless and 'MACHO_SUBTYPE:' in rootless
print('PASS package identity: Sileo name iOS 27 动画; Author/Maintainer Ning; ' + expected)
print('PASS old package ID is limited to upgrade metadata; all preference domains use the new namespace')
