#!/usr/bin/env python3
"""Static resource checks; not a substitute for UIKit/device visual testing."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct

ROOT = Path(__file__).resolve().parents[1]
PREFS = ROOT / 'iOS27Animations/Prefs'
manifest = json.loads((ROOT / 'tests/fixtures/settings-icon.json').read_text())
source = ROOT / manifest['source']['path']
assert hashlib.sha256(source.read_bytes()).hexdigest() == manifest['source']['sha256']
assert manifest['source']['sha256'] == '60ffe30ab3a6f3105329294bcf94dfcb6609352e095fd01a66855fc59b41485a'
for name, entry in manifest['exports'].items():
    raw = (PREFS / 'Resources' / name).read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n'
    assert list(struct.unpack('>II', raw[16:24])) == entry['pixels']
    assert raw[24:26] == bytes([8, 6]), '8-bit RGBA PNG required'
    assert hashlib.sha256(raw).hexdigest() == entry['sha256'], name
entry = plistlib.loads((PREFS / 'layout/Library/PreferenceLoader/Preferences/iOS2627AnimsPrefs.plist').read_bytes())['entry']
assert entry['icon'] == 'icon.png' and entry['isController'] is True
rows = plistlib.loads((PREFS / 'Resources/Root.plist').read_bytes())['items']
assert not any('iconSymbol' in x for x in rows)
assert not any(x.get('action') in ('openTelegram', 'openChannel', 'openGitHub') for x in rows)
assert not any(x.get('label') == 'Author' or x.get('footerText') == 'version' for x in rows)
controller = (PREFS / 'CG27RootListController.m').read_text()
for removed in ('CG27Prepare', 'CG27Icon', 'showPrompt', 'by bazik1337', 'kCG27Telegram', 'kCG27Channel', 'kCG27GitHub'):
    assert removed not in controller, removed
assert 'cell.textLabel.textColor = UIColor.labelColor;' in controller
assert 'slider.tintColor = UIColor.systemBlueColor;' in controller
assert 'slider.minimumTrackTintColor = UIColor.systemBlueColor;' in controller
assert controller.count('CG27ApplySliderTint(cell.contentView);') == 2
print('PASS: user-selected icon at 29/58/87px; entry reference; removed author/promotions/row-icons; shared blue-slider and system-label styling (static checks)')
