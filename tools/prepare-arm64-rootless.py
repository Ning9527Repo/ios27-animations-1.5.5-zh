#!/usr/bin/env python3
"""Create an isolated rootless dual-slice (arm64+arm64e) build tree."""
import pathlib
import shutil
import sys

source = pathlib.Path(__file__).resolve().parents[1]
out = pathlib.Path(sys.argv[1]).resolve()
if out.exists():
    raise SystemExit(f"refusing to overwrite existing staging directory: {out}")
shutil.copytree(source, out, ignore=shutil.ignore_patterns(
    ".git", ".theos", "packages", "__pycache__", ".DS_Store"
))

def replace(path, old, new, count=1):
    file = out / path
    text = file.read_text()
    found = text.count(old)
    if found != count:
        raise SystemExit(f"{path}: expected {count} occurrences, found {found}")
    file.write_text(text.replace(old, new))

# Baseline source is RootHide arm64e; convert to rootless dual-slice.
replace("iOS27Animations/Makefile",
        "ARCHS = arm64e\nTHEOS_PACKAGE_SCHEME = roothide\n",
        "ARCHS = arm64 arm64e\nTHEOS_PACKAGE_SCHEME = rootless\n")
replace("iOS27Animations/Prefs/Makefile", "ARCHS = arm64e\n",
        "ARCHS = arm64 arm64e\n")
replace("iOS27Animations/control",
        "Version: 0.3\nArchitecture: iphoneos-arm64e",
        "Version: 0.3.2\nArchitecture: iphoneos-arm64")
replace("iOS27Animations/layout/Library/libSandy/iOS27Animations_SwitchReadConfig.plist",
        "/rootfs/var/mobile/Library/Accessibility/", "/var/mobile/Library/Accessibility/")
replace("iOS27Animations/layout/Library/libSandy/KeyboardGlass_ReadConfig.plist",
        "/rootfs/var/mobile/Library/Accessibility/", "/var/mobile/Library/Accessibility/")
print(f"prepared rootless dual-slice arm64/arm64e tree: {out}")
