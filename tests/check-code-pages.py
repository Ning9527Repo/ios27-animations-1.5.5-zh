#!/usr/bin/env python3
"""Verify signed code pages in thin or fat arm64/arm64e Mach-O files."""
import hashlib,json,pathlib,struct,subprocess,sys,tempfile,os

CPU=0x100000c
SUB={'arm64':0x0,'arm64e':0x80000002}

def thin(data, expected_sub, label):
    assert data[:4]==b'\xcf\xfa\xed\xfe', label
    _,cpu,sub,ft,n,sz,flags,_=struct.unpack_from('<8I',data)
    assert cpu==CPU and sub==expected_sub and ft in (6,8),(label,hex(cpu),hex(sub))
    off=32; signature=None; minimum=None
    for _ in range(n):
        cmd,size=struct.unpack_from('<II',data,off); assert size>=8 and off+size<=32+sz
        if cmd==0x1d: signature=struct.unpack_from('<II',data,off+8)
        if cmd==0x32:
            platform,minimum=struct.unpack_from('<II',data,off+8); assert platform==2
        if cmd==0x25: minimum=struct.unpack_from('<I',data,off+8)[0]
        off+=size
    assert off==32+sz and minimum==0x100000 and signature
    pos,size=signature; assert pos+size<=len(data)
    magic,length,count=struct.unpack_from('>III',data,pos); assert magic==0xfade0cc0 and length<=size
    reports=[]
    for i in range(count):
        typ,rel=struct.unpack_from('>II',data,pos+12+8*i)
        if typ!=0 and not 0x1000<=typ<=0x1005: continue
        base=pos+rel; magic,length,version,flags,hashoff,ident,nsp,ncode,limit=struct.unpack_from('>9I',data,base)
        assert magic==0xfade0c02 and rel+length<=size
        hsize,htype,platform,pexp=struct.unpack_from('4B',data,base+36)
        digest={1:hashlib.sha1,2:hashlib.sha256,3:hashlib.sha256,4:hashlib.sha384}[htype]
        pagesize=1<<pexp; assert ncode==(limit+pagesize-1)//pagesize and limit<=pos
        for k in range(ncode):
            got=digest(data[k*pagesize:min((k+1)*pagesize,limit)]).digest()[:hsize]
            assert got==data[base+hashoff+k*hsize:base+hashoff+(k+1)*hsize],(label,'code page',k)
        reports.append({'hash_type':htype,'page_bytes':pagesize,'pages':ncode})
    assert reports
    return {'subtype':hex(expected_sub),'signed_code_pages':reports}

def machos(data,label):
    if data[:4]==b'\xca\xfe\xba\xbe':
        _,n=struct.unpack_from('>II',data); out=[]
        for i in range(n):
            cpu,sub,off,size,align=struct.unpack_from('>IIIII',data,8+20*i)
            assert cpu==CPU and sub in SUB.values(),(label,hex(cpu),hex(sub))
            name=next(k for k,v in SUB.items() if v==sub)
            out.append({'arch':name,**thin(data[off:off+size],sub,label+':'+name)})
        assert {x['arch'] for x in out}=={'arm64','arm64e'},(label,out)
        return out
    return [dict(arch=next(k for k,v in SUB.items() if v==struct.unpack_from('<I',data,8)[0]),**thin(data,struct.unpack_from('<I',data,12)[0],label))]

def verify(path):
 with tempfile.TemporaryDirectory() as tmp:
  subprocess.run(['dpkg-deb','-x',str(path),tmp],check=True); d=pathlib.Path(tmp); results=[]
  for p in sorted(d.rglob('*')):
   if p.is_file() and p.read_bytes()[:4] in (b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe'):
    results.append({'path':p.relative_to(d).as_posix(),'slices':machos(p.read_bytes(),str(p))})
  assert len(results)==2,results
 report={'package':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'mach_o':results,'status':'passed'}
 arch=os.environ.get('PACKAGE_ARCH','iphoneos-arm64'); (path.parent/f'{arch}-metadata.json').write_text(json.dumps(report,indent=2)+'\n'); print(json.dumps(report,indent=2))
if __name__=='__main__':
 for arg in sys.argv[1:]: verify(pathlib.Path(arg))
