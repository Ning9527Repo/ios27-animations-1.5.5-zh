#!/usr/bin/env python3
"""Read final package Mach-O metadata and verify every signed code page."""
import hashlib,json,pathlib,struct,subprocess,sys,tempfile,os

def check(data):
 assert data[:4]==b'\xcf\xfa\xed\xfe'
 _,cpu,sub,ft,n,sz,flags,_=struct.unpack_from('<8I',data)
 import os
 expected_sub=int(os.environ.get('MACHO_SUBTYPE','0x80000002'),0)
 assert cpu==0x100000c and sub==expected_sub and ft in (6,8)
 off=32;signature=None;minimum=None
 for _ in range(n):
  cmd,size=struct.unpack_from('<II',data,off);assert size>=8 and off+size<=32+sz
  if cmd==0x1d: signature=struct.unpack_from('<II',data,off+8)
  if cmd==0x32:
   platform,minimum=struct.unpack_from('<II',data,off+8);assert platform==2
  if cmd==0x25: minimum=struct.unpack_from('<I',data,off+8)[0]
  off+=size
 assert off==32+sz and minimum==0x100000 and signature
 pos,size=signature;assert pos+size<=len(data)
 magic,length,count=struct.unpack_from('>III',data,pos)
 assert magic==0xfade0cc0 and length<=size
 reports=[]
 for i in range(count):
  typ,rel=struct.unpack_from('>II',data,pos+12+8*i)
  if typ!=0 and not 0x1000<=typ<=0x1005: continue
  base=pos+rel;magic,length,version,flags,hashoff,ident,nsp,ncode,limit=struct.unpack_from('>9I',data,base)
  assert magic==0xfade0c02 and rel+length<=size
  hsize,htype,platform,pexp=struct.unpack_from('4B',data,base+36)
  digest={1:hashlib.sha1,2:hashlib.sha256,3:hashlib.sha256,4:hashlib.sha384}[htype]
  pagesize=1<<pexp
  assert ncode==(limit+pagesize-1)//pagesize and limit<=pos
  for k in range(ncode):
   got=digest(data[k*pagesize:min((k+1)*pagesize,limit)]).digest()[:hsize]
   assert got==data[base+hashoff+k*hsize:base+hashoff+(k+1)*hsize],('code page',k)
  reports.append({'hash_type':htype,'page_bytes':pagesize,'pages':ncode})
 assert reports
 return {'cpu_subtype':hex(sub),'minimum_ios':'16.0','signed_code_pages':reports}

def verify(path):
 with tempfile.TemporaryDirectory() as tmp:
  subprocess.run(['dpkg-deb','-x',str(path),tmp],check=True)
  d=pathlib.Path(tmp);results=[]
  for p in sorted(d.rglob('*')):
   if p.is_file():
    data=p.read_bytes()
    if data[:4]==b'\xcf\xfa\xed\xfe': results.append({'path':p.relative_to(d).as_posix(),**check(data)})
  assert len(results)==2,results
 report={'package':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'mach_o':results,'status':'passed'}
 arch=os.environ.get('PACKAGE_ARCH','arm64e')
 (path.parent/f'{arch}-metadata.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,indent=2))
if __name__=='__main__':
 for arg in sys.argv[1:]: verify(pathlib.Path(arg))
