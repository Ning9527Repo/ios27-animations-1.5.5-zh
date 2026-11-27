#!/usr/bin/env python3
"""Verify a real rootless arm64/arm64e fat package and signed binaries."""
import hashlib
import json
import pathlib
import plistlib
import struct
import subprocess
import sys
import tarfile
import tempfile
import io

root = pathlib.Path(__file__).resolve().parents[1]
pkgs = pathlib.Path(sys.argv[1])
debs = list(pkgs.glob("*.deb"))
assert len(debs) == 1, debs
package = debs[0]
def run(*args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{args[0]} exited {result.returncode}: {result.stderr[-2500:]}")
    return result.stdout

with tempfile.TemporaryDirectory(prefix="ios27-arm64-verify-") as tmp:
    dest = pathlib.Path(tmp)
    control = run("dpkg-deb", "-f", str(package))
    fields = dict(line.split(": ", 1) for line in control.splitlines() if ": " in line)
    assert fields["Package"] == "com.ning.ios2627anims", fields
    assert fields["Version"] == "0.3.2" and fields["Architecture"] == "iphoneos-arm64", fields
    assert fields["Author"] == fields["Maintainer"] == "Ning", fields
    assert fields["Name"] == "iOS 27 动画" and "Icon" not in fields, fields
    assert package.name == f"{fields['Package']}_{fields['Version']}_{fields['Architecture']}.deb"
    assert "com.opa334.libsandy" in fields["Depends"]
    run("dpkg-deb", "-x", str(package), str(dest))
    raw = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(package)])
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        members = {m.name.lstrip("./"): m for m in archive.getmembers()}
    files = [p.relative_to(dest).as_posix() for p in dest.rglob("*") if p.is_file()]
    assert not any(p.startswith("Library/") for p in files), files
    assert all(p.startswith("var/jb/") or p.startswith("usr/") or p.startswith("DEBIAN/") for p in files), files
    profile_expectations = {
        "iOS27Animations_SwitchReadConfig.plist": "/var/mobile/Library/Accessibility/iOS27Animations-switch.plist",
        "KeyboardGlass_ReadConfig.plist": "/var/mobile/Library/Accessibility/KeyboardGlass-preferences.plist",
    }
    for name, allowed in profile_expectations.items():
        profile = dest / "var/jb/Library/libSandy" / name
        assert plistlib.loads(profile.read_bytes()) == {
            "AllowedProcesses": ["*"],
            "Extensions": [{"type": "file", "extension_class": "com.apple.app-sandbox.read", "path": allowed}],
        }
        member = members["var/jb/Library/libSandy/" + name]
        assert member.uid == member.gid == 0 and member.mode == 0o644
    prefs = dest / "var/jb/Library/PreferenceBundles/iOS2627AnimsPrefs.bundle"
    main = dest / "var/jb/Library/MobileSubstrate/DynamicLibraries/iOS2627Anims.dylib"
    app = prefs / "iOS2627AnimsPrefs"
    resource = dest / "var/jb/Library/Application Support/iOS27Animations/TheseusSwitchResources.bundle"
    assert main.is_file() and app.is_file() and (resource / "default.metallib").stat().st_size > 1000
# The package and preference bundle versions are independently checked.
    assert plistlib.loads((resource / "Info.plist").read_bytes())["CFBundleVersion"] == "0.3"
    assert sorted(p.relative_to(dest).as_posix() for p in dest.rglob("*.dylib")) == ["var/jb/Library/MobileSubstrate/DynamicLibraries/iOS2627Anims.dylib"]
    assert plistlib.loads((prefs / "Info.plist").read_bytes())["CFBundleShortVersionString"] == "0.3"
    entry = plistlib.loads((dest / "var/jb/Library/PreferenceLoader/Preferences/iOS2627AnimsPrefs.plist").read_bytes())["entry"]
    assert entry["label"] == "iOS 27 动画" and entry["icon"] == "icon.png" and entry["isController"] is True
    rows = plistlib.loads((prefs / "Root.plist").read_bytes())["items"]
    assert rows == plistlib.loads((root / "iOS27Animations/Prefs/Resources/Root.plist").read_bytes())["items"]
    def slices(binary):
        data = binary.read_bytes()
        assert data[:4] == b"\xca\xfe\xba\xbe", binary
        _, count = struct.unpack_from(">II", data)
        found = {}
        for i in range(count):
            cpu, subtype, offset, size, align = struct.unpack_from(">IIIII", data, 8 + 20 * i)
            assert cpu == 0x100000c and subtype in (0, 0x80000002), (binary, hex(cpu), hex(subtype))
            thin = data[offset:offset + size]
            assert thin[:4] == b"\xcf\xfa\xed\xfe"
            t_cpu, t_subtype = struct.unpack_from("<II", thin, 4)
            assert (t_cpu, t_subtype) == (cpu, subtype)
            found[subtype] = {"bytes": size, "sha256": hashlib.sha256(thin).hexdigest()}
        assert set(found) == {0, 0x80000002}, (binary, found)
        return found
    binaries = []
    for binary in (main, app):
        binaries.append({"path": binary.relative_to(dest).as_posix(), "slices": slices(binary)})
        run("codesign", "--verify", "--strict", "--verbose=4", str(binary))
    report = {
        "status": "passed", "filename": package.name, "bytes": package.stat().st_size,
        "sha256": hashlib.sha256(package.read_bytes()).hexdigest(), "control": fields,
        "mach_o": binaries, "file_count": len(files), "rootless_layout": "var/jb/",
        "libSandy_profiles": "native /var/mobile paths",
    }
    (pkgs / "verification-arm64.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
