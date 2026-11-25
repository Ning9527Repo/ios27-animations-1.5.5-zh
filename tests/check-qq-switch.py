#!/usr/bin/env python3
"""QQ-only boundaries; exact baseline comparisons plus production-code stand-ins."""
from pathlib import Path
import hashlib, json, re, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
f = root / 'iOS27Animations/SwitchFeature'
sw = (f/'Vendor/Theseus/Sources/Theseus/Components/TheseusSwitch.swift').read_text()
qq = (f/'src/NGQQSwitch.m').read_text()
bridge = (f/'src/NGQQBridge.swift').read_text()
baseline = json.loads((root/'tests/qq-baseline.json').read_text())
def digest(text): return hashlib.sha256(text.encode()).hexdigest()
for rel, sha in baseline['unchanged'].items():
    data=(root/rel).read_bytes()
    assert hashlib.sha256(data).hexdigest() == sha, ('baseline changed', rel)
# Remove ONLY the new early QQ returns. Non-QQ/Clock runtime is then byte-identical.
core = (f/'src/NGSwitch.m').read_text()
core, count = re.subn(r'^    if \(NGIsQQSwitchHost\(\)\).*\n', '', core, flags=re.M)
assert count == 6 and digest(core) == baseline['normalized_core']
original = sw
original = re.sub(r'    // QQ-only visual adapter:.*?(?=    var clockTouchActive:)', '', original, flags=re.S)
original = original.replace('        if let provider = qqCaptureSourceProvider { return provider() }\n', '')
original = original.replace('if isolatesClockCapture || qqCaptureSourceProvider != nil {', 'if isolatesClockCapture {')
original = re.sub(r'        if qqCaptureSourceProvider != nil \{\n            // A transparent.*?(?=        glass.isHidden = true)', '', original, flags=re.S)
original = original.replace('        if let owner = qqOwnerIsCurrent, !owner() { return }\n', '')
original = original.replace('        if let owner = qqOwnerIsCurrent, !owner() {\n            qqCancelNativeVisual()\n            return\n        }\n', '')
original = original.replace('        if qqCaptureSourceProvider == nil { hapticFeedback.impact(.light) }', '        hapticFeedback.impact(.light)')
original = re.sub(r'    // QQ visuals observe native UISwitch input\..*?(?=    @objc private func handlePress)', '', original, flags=re.S)
assert digest(original) == baseline['normalized_switch'], 'non-QQ component logic diverged from 1.5.7'
assert '[NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.tencent.mqq"]' in qq
assert not re.search(r'sendActions|\[source setOn:|source\.on\s*=|source\.alpha\s*=|hitTest:', qq)
assert 'cancelsTouchesInView = NO' in qq and 'delaysTouchesBegan = NO' in qq and 'delaysTouchesEnded = NO' in qq
assert 'return NO;' in qq.split('canPreventGestureRecognizer:')[1].split('}')[0]
assert 'return NO;' in qq.split('canBePreventedByGestureRecognizer:')[1].split('}')[0]
assert 'self.parent != source.superview' in qq and 'path isEqual:self.path' in qq
assert 'binding.generation != generation' in qq and 'binding.source.isOn cancelled:cancelled' in qq
assert 'if (!binding.touching && !binding.ending)' in qq
assert 'toggle.isUserInteractionEnabled = false' in bridge and 'toggle.removeGestureRecognizer' in bridge
assert 'return localRow ?? native.window?.rootViewController?.view' in bridge
assert 'return localRow ?? native' not in bridge.replace('return localRow ?? native.window', '')
assert 'color.cgColor.alpha >= 0.99' in bridge and 'UIColor.systemBackground.resolvedColor' in bridge
assert 'source.layer.insertSublayer(backing, at: 0)' in sw and 'backing.removeFromSuperlayer()' in sw
assert 'qqOwnerIsCurrent?() == true' in sw
mk = (root/'iOS27Animations/Makefile').read_text()
assert 'src/NGQQSwitch.m' in mk and 'src/NGQQBridge.swift' in mk
print('PASS QQ-only scope: non-QQ/Clock paths normalize byte-for-byte to 1.5.7; renderer/shader/configuration unchanged')
# Compile the exact production QQ binding/mask/lifecycle code against native
# Foundation/QuartzCore with minimal UIKit substitutes. This is not a device test.
source = qq[qq.index('BOOL NGIsQQSwitchHost(void)'):]
a = source.index('@implementation NGQQTouchObserver\n')
b = source.index('\n@end', a) + len('\n@end')
source = source[:a] + '@implementation NGQQTouchObserver @end' + source[b:]
source = source.replace('return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.tencent.mqq"];', 'return YES;')
fixture = (root/'tests/qq-native-owner.m').read_text().replace('/* PRODUCTION_QQ */', source)
with tempfile.TemporaryDirectory() as tmp:
    d = Path(tmp); p = d/'qq.m'; p.write_text(fixture)
    if sys.platform == 'darwin':
        exe = d/'qq'
        subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',str(p),
                        '-framework','Foundation','-framework','CoreGraphics','-framework','QuartzCore','-o',str(exe)], check=True)
        subprocess.run([str(exe)], check=True)
        swift = (root/'tests/qq-native-visual.swift').read_text()
        a = sw.index('    func qqBeginNativeTouch('); b = sw.index('\n    @objc private func handlePress', a)
        swift = swift.replace('/* PRODUCTION_QQ_METHODS */', sw[a:b])
        p = d/'qq.swift'; p.write_text(swift)
        subprocess.run(['swift', str(p)], check=True)
    else:
        subprocess.run(['clang','-fsyntax-only','-target','arm64e-apple-ios15.0','-isysroot',
                        '/var/minis/shared/sdks/iPhoneOS16.5.sdk','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',str(p)], check=True)
        print('PASS extracted QQ production strict syntax; native execution is macOS-only')
