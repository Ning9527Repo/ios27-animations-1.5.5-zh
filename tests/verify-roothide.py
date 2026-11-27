#!/usr/bin/env python3
import pathlib,sys,tempfile,subprocess,struct,json,hashlib,plistlib,tarfile,io
root=pathlib.Path(__file__).resolve().parents[1]
pkgs=pathlib.Path(sys.argv[1]); debs=list(pkgs.glob('*.deb'))
assert len(debs)==1,debs
p=debs[0]
def run(*args):
    result=subprocess.run(args,text=True,capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{args[0]} exited {result.returncode}: {result.stderr.strip()[-3000:]}')
    return result.stdout
with tempfile.TemporaryDirectory() as tmp:
    d=pathlib.Path(tmp)
    control=run('dpkg-deb','-f',str(p))
    fields=dict(x.split(': ',1) for x in control.splitlines() if ': ' in x)
    assert fields['Architecture']=='iphoneos-arm64e',fields
    assert fields['Version']=='0.3.3',fields
    assert fields['Author']=='Ning',fields
    assert fields['Maintainer']=='Ning',fields
    assert fields['Package']=='com.ning.ios2627anims',fields
    assert fields['Name']=='iOS 27 动画' and 'Icon' not in fields,fields
    assert p.name==f"{fields['Package']}_{fields['Version']}_{fields['Architecture']}.deb",p.name
    assert 'com.bazik1337.ios2627anims' in fields['Conflicts'].split(', '),fields
    assert 'com.bazik1337.ios2627anims' in fields['Replaces'].split(', '),fields
    assert 'com.opa334.libsandy' in fields['Depends'],fields
    run('dpkg-deb','-x',str(p),str(d))
    archive=subprocess.check_output(['dpkg-deb','--fsys-tarfile',str(p)])
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        members={x.name.lstrip('./'):x for x in tar.getmembers()}
    profile=d/'Library/libSandy/iOS27Animations_SwitchReadConfig.plist'
    assert plistlib.loads(profile.read_bytes())=={'AllowedProcesses':['*'],'Extensions':[{'type':'file','extension_class':'com.apple.app-sandbox.read','path':'/rootfs/var/mobile/Library/Accessibility/iOS27Animations-switch.plist'}]}
    kgread=d/'Library/libSandy/KeyboardGlass_ReadConfig.plist'
    assert plistlib.loads(kgread.read_bytes())=={'AllowedProcesses':['*'],'Extensions':[{'type':'file','extension_class':'com.apple.app-sandbox.read','path':'/rootfs/var/mobile/Library/Accessibility/KeyboardGlass-preferences.plist'}]}
    for item in (profile,kgread):
        assert item.stat().st_mode & 0o777 == 0o644
    assert plistlib.loads((d/'Library/PreferenceBundles/iOS2627AnimsPrefs.bundle/KeyboardGlass.plist').read_bytes())['items']
    assert (d/f'Library/PreferenceBundles/iOS2627AnimsPrefs.bundle/zh-Hans.lproj/KeyboardGlass.strings').is_file()
    for profile_name in ('iOS27Animations_SwitchReadConfig.plist','KeyboardGlass_ReadConfig.plist'):
        member=members.get('Library/libSandy/'+profile_name)
        assert member is not None,profile_name
        assert member.uid==member.gid==0 and member.mode==0o644,(member.name,member.uid,member.gid,member.mode)
    files=[x.relative_to(d).as_posix() for x in d.rglob('*') if x.is_file()]
    assert not any(x.startswith('var/jb/') for x in files),files
    lib=d/'Library/MobileSubstrate/DynamicLibraries/iOS2627Anims.dylib'
    prefs=d/'Library/PreferenceBundles/iOS2627AnimsPrefs.bundle'
    app=prefs/'iOS2627AnimsPrefs'
    assert lib.is_file() and app.is_file()
    resource=d/'Library/Application Support/iOS27Animations/TheseusSwitchResources.bundle'
    assert (resource/'default.metallib').stat().st_size>1000
    assert plistlib.loads((resource/'Info.plist').read_bytes())['CFBundleVersion']=='0.3'
    assert sorted(x.relative_to(d).as_posix() for x in d.rglob('*.dylib'))==['Library/MobileSubstrate/DynamicLibraries/iOS2627Anims.dylib']
    switch_rows=plistlib.loads((prefs/'Root.plist').read_bytes())['items']
    assert sum(x.get('key')=='LiquidSwitchEnabled' for x in switch_rows)==1
    assert switch_rows[6].get('key')=='KeyboardGlassEnabled' and switch_rows[6].get('label')=='Enabled'
    assert switch_rows[6].get('defaults')=='com.ning.keyboardglass'
    for name in ('LICENSE','NOTICE','vendor-manifest.json'):
        assert (d/'usr/share/doc/com.ning.ios2627anims/Theseus'/name).is_file()
    entry=plistlib.loads((d/'Library/PreferenceLoader/Preferences/iOS2627AnimsPrefs.plist').read_bytes())['entry']
    assert entry['icon']=='icon.png' and entry['isController'] is True
    icon_manifest=json.loads((root/'tests/fixtures/settings-icon.json').read_text())
    for name,expected in icon_manifest['exports'].items():
        raw=(prefs/name).read_bytes()
        assert raw[:8]==b'\x89PNG\r\n\x1a\n' and raw[24:26]==bytes([8,6])
        assert list(struct.unpack('>II',raw[16:24]))==expected['pixels']
        assert hashlib.sha256(raw).hexdigest()==expected['sha256'],name
    assert not any(x.startswith('usr/share/icons/') for x in files),'unexpected Sileo package artwork'
    assert switch_rows==plistlib.loads((root/'iOS27Animations/Prefs/Resources/Root.plist').read_bytes())['items']
    for page in ('Root','AppAnimations','NotificationCenter','Advanced'):
        assert (prefs/'zh-Hans.lproj'/(page+'.strings')).is_file()
    assert (prefs/'AppAnimations.plist').is_file() and (prefs/'NotificationCenter.plist').is_file()
    app_rows=plistlib.loads((prefs/'AppAnimations.plist').read_bytes())['items']
    assert [x.get('label') for x in app_rows if x.get('cell')=='PSGroupCell']==[None,'Notification Center','Advanced']
    assert not any(x.get('cell')=='PSLinkCell' for x in app_rows)
    assert [x['key'] for x in app_rows if 'key' in x]==['AppAnimations','OpenSpeed','CloseSpeed','IconFlyIn','ClearSheet','Intensity','GestureBounce','FlyStrength','GlobalSlow']
    assert plistlib.loads((prefs/'Info.plist').read_bytes())['CFBundleShortVersionString']=='0.3.3'
    out=[]
    for f in (lib,app):
        data=f.read_bytes()
        assert data[:4]==b'\xcf\xfa\xed\xfe',(str(f),data[:4])
        cpu,sub=struct.unpack_from('<II',data,4)
        assert cpu==0x100000c and sub==0x80000002,(f,hex(cpu),hex(sub))
        signed=run('codesign','--verify','--strict','--verbose=4',str(f))
        out.append({'path':f.relative_to(d).as_posix(),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'subtype':hex(sub),'signature':'strict-pass'})
    report={'status':'passed','filename':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'control':fields,'mach_o':out,'file_count':len(files)}
    (pkgs/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
