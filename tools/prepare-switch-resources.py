#!/usr/bin/env python3
"""Compile the vendored Theseus shader resource; does not build a dylib or deb."""
import pathlib, plistlib, subprocess, sys, shutil
root=pathlib.Path(__file__).resolve().parents[1]
out=pathlib.Path(sys.argv[1]).resolve()
if out.exists(): shutil.rmtree(out)
bundle=out/'TheseusSwitchResources.bundle'; bundle.mkdir(parents=True)
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
source=root/'iOS27Animations/SwitchFeature/Vendor/Theseus/Sources/Theseus/Shaders/TheseusShaders.metal'
air=out/'TheseusShaders.air'
subprocess.run(['xcrun','--sdk','iphoneos','metal','-target','air64-apple-ios15.0','-isysroot',sdk,'-std=ios-metal2.4','-O2','-I',str(source.parent),'-c',str(source),'-o',str(air)],check=True)
subprocess.run(['xcrun','--sdk','iphoneos','metallib',str(air),'-o',str(bundle/'default.metallib')],check=True)
info={'CFBundleIdentifier':'com.bazik1337.ios2627anims.switchresources','CFBundleName':'TheseusSwitchResources','CFBundlePackageType':'BNDL','CFBundleVersion':'1.5.9.1'}
(bundle/'Info.plist').write_bytes(plistlib.dumps(info,fmt=plistlib.FMT_XML,sort_keys=True))
print(f'compiled integrated resource: {bundle}')
