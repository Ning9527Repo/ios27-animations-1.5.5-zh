#!/usr/bin/env python3
import pathlib,sys,tempfile,subprocess,struct,json,hashlib,plistlib
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
    assert fields['Version']=='1.5.5+ningzh1',fields
    assert fields['Author']=='Ning&bazik1337',fields
    assert fields['Maintainer']=='Ning&bazik1337',fields
    run('dpkg-deb','-x',str(p),str(d))
    files=[x.relative_to(d).as_posix() for x in d.rglob('*') if x.is_file()]
    assert not any(x.startswith('var/jb/') for x in files),files
    lib=d/'Library/MobileSubstrate/DynamicLibraries/iOS2627Anims.dylib'
    prefs=d/'Library/PreferenceBundles/iOS2627AnimsPrefs.bundle'
    app=prefs/'iOS2627AnimsPrefs'
    assert lib.is_file() and app.is_file()
    assert (d/'Library/PreferenceLoader/Preferences/iOS2627AnimsPrefs.plist').is_file()
    for page in ('Root','Advanced'):
        assert (prefs/'zh-Hans.lproj'/(page+'.strings')).is_file()
    assert plistlib.loads((prefs/'Info.plist').read_bytes())['CFBundleShortVersionString']=='1.5.5'
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
