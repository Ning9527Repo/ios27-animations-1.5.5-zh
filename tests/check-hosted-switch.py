#!/usr/bin/env python3
"""Extract production ownership code for native host regressions; no UIKit claim."""
from pathlib import Path
import json,subprocess,sys,tempfile
root=Path(__file__).resolve().parents[1]
f=root/'iOS27Animations/SwitchFeature'
s=(f/'src/NGSwitch.m').read_text()
sw=(f/'Vendor/Theseus/Sources/Theseus/Components/TheseusSwitch.swift').read_text()
bridge=(f/'src/TheseusBridge.swift').read_text()
assert 'binding.sourceHosted = !NGIsClock();' in s
assert '[source addSubview:binding.overlay]' in s and 'NGMaskHostedNativeLayers(source, binding);' in s
assert 'if (!binding.sourceHosted && source.alpha != 0)' in s
assert 'if confinesHostedGlass { return self }' in sw
assert 'if isolatesClockCapture || confinesHostedGlass { return self }' in sw
assert 'guard interactionGeneration == releaseGeneration' in sw
assert 'guard hostedPressIsCurrent else' in sw and 'if !hostedPressIsCurrent {' in sw
assert 'currentHostedIdentity' in bridge
assert 'table.indexPath(for: cell)' in bridge and 'collection.indexPath(for: cell)' in bridge
src=(root/'tests/hosted-switch.m').read_text()
a=s.index('@interface NGSwitchNativeMask');b=s.index('static void NGMaskHostedNativeLayers',a)
src=src.replace('/* PRODUCTION_BINDING_INTERFACE */',s[a:b])
a=s.index('@implementation NGSwitchBinding\n');b=s.index('\n@end',a)+len('\n@end')
src=src.replace('/* PRODUCTION_BINDING_IMPLEMENTATION */',s[a:b])
a=s.index('static void NGMaskHostedNativeLayers');b=s.index('// A replay ticket belongs',a)
src=src.replace('/* PRODUCTION_MASK_HELPERS */',s[a:b])
a=s.index('static void NGApplySwitchGeometry');b=s.index('\nvoid NGSyncSwitchGeometry',a)
src=src.replace('/* PRODUCTION_GEOMETRY */',s[a:b])
with tempfile.TemporaryDirectory() as tmp:
    d=Path(tmp);p=d/'hosted.m';p.write_text(src)
    if sys.platform=='darwin':
        binary=d/'hosted'
        subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',str(p),
            '-framework','Foundation','-framework','CoreGraphics','-framework','QuartzCore','-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True)
        # Run the exact production identity gate and finishPress control flow.
        swift=(root/'tests/hosted-identity.swift').read_text()
        start=sw.index('struct HostedSwitchIdentity:');end=sw.index('\n/// A Liquid Glass',start)
        swift=swift.replace('/* PRODUCTION_IDENTITY */',sw[start:end])
        start=sw.index('    private var hostedPressIsCurrent:');end=sw.index('\n    var clockTouchActive',start)
        swift=swift.replace('/* PRODUCTION_GATE */',sw[start:end])
        start=sw.index('    private func finishPress(cancelled:');end=sw.index('\n    /// Visual-only recovery',start)
        swift=swift.replace('/* PRODUCTION_FINISH */',sw[start:end])
        p=d/'identity.swift';p.write_text(swift)
        subprocess.run(['swift',str(p)],check=True)
    else:
        subprocess.run(['clang','-fsyntax-only','-target','arm64e-apple-ios15.0','-isysroot',
            '/var/minis/shared/sdks/iPhoneOS16.5.sdk','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',str(p)],check=True)
        print('PASS production hosted binding/mask/geometry strict syntax; native execution scheduled in CI')
