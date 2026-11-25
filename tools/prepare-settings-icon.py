#!/usr/bin/env python3
"""Export the user-approved Settings entry artwork, without recolouring/cropping."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'artwork/settings-icon-source.png'
RES = ROOT / 'iOS27Animations/Prefs/Resources'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

with Image.open(SOURCE) as source:
    assert source.format == 'PNG' and source.mode == 'RGBA' and source.size == (400, 400)
    assert source.getpixel((0, 0))[3] == 0
    manifest = {'source': {'path': SOURCE.relative_to(ROOT).as_posix(),
                           'sha256': sha(SOURCE), 'pixels': list(source.size)},
                'exports': {}}
    for scale in (1, 2, 3):
        size = 29 * scale
        name = 'icon' + (f'@{scale}x' if scale > 1 else '') + '.png'
        out = RES / name
        image = source.resize((size, size), Image.Resampling.LANCZOS)
        image.save(out, format='PNG', optimize=True, compress_level=9)
        with Image.open(out) as check:
            assert check.size == (size, size) and check.mode == 'RGBA'
            assert check.getpixel((0, 0))[3] == 0
        manifest['exports'][name] = {'pixels': [size, size], 'sha256': sha(out)}
(ROOT / 'tests/fixtures/settings-icon.json').write_text(
    json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
