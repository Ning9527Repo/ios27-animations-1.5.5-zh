#!/usr/bin/env python3
"""Compile production snapshot helpers + exact apply function on macOS Foundation."""
import pathlib,sys,subprocess,tempfile,os
root=pathlib.Path(__file__).resolve().parents[1]
hooks=(root/'iOS27Animations/SwitchFeature/src/Tweak.m').read_text()
start=hooks.index('static void NGApplySwitchFeaturePreference(')
end=hooks.index('\nstatic void NGRecoverSwitchConfiguration',start)
source=(root/'tests/switch-configuration.m').read_text().replace('/* PRODUCTION_APPLY */',hooks[start:end])
with tempfile.TemporaryDirectory() as temp:
    d=pathlib.Path(temp);m=d/'configuration.m';m.write_text(source);binary=d/'configuration'
    if sys.platform!='darwin':
        sdk='/var/minis/shared/sdks/iPhoneOS16.5.sdk'
        target = 'arm64-apple-ios15.0' if os.environ.get('PACKAGE_SCHEME') == 'rootless' else 'arm64e-apple-ios15.0'
        subprocess.run(['clang','-fsyntax-only','-target',target,'-isysroot',sdk,
                        '-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror','-I',str(root),str(m)],check=True)
        print('PASS strict arm64e syntax for production configuration harness; native Foundation execution deferred to macOS')
    else:
        subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',
                        '-I',str(root),str(m),'-framework','Foundation','-framework','CoreFoundation','-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True)
        path=d/'shared/switch.plist'
        for enabled in ('1','0','1'):
            subprocess.run([str(binary),'write',str(path),enabled],check=True)
            subprocess.run([str(binary),'read',str(path),enabled],check=True)
            assert os.stat(path).st_mode&0o777==0o644
        print('PASS independent producer/consumer process round trips ON/OFF/ON (not a sandbox or UIKit device test)')
