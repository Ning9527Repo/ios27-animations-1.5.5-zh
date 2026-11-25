#!/usr/bin/env python3
"""Normalize deb archive ownership without modifying any packaged file bytes."""
import argparse,copy,gzip,hashlib,io,json,lzma,pathlib,tarfile

def members(data):
    assert data[:8]==b'!<arch>\n'
    result=[];offset=8
    while offset<len(data):
        header=data[offset:offset+60]
        assert len(header)==60 and header[58:60]==b'`\n'
        size=int(header[48:58]);body=data[offset+60:offset+60+size]
        assert len(body)==size
        result.append((header,header[:16].decode().strip().rstrip('/'),body))
        offset+=60+size+(size&1)
    assert offset==len(data)
    return result

def tar_bytes(name,data):
    if name.endswith('.lzma'):return lzma.decompress(data,format=lzma.FORMAT_ALONE)
    if name.endswith('.xz'):return lzma.decompress(data,format=lzma.FORMAT_XZ)
    if name.endswith('.gz'):return gzip.decompress(data)
    raise ValueError('unsupported tar compression: '+name)

def compress(name,data):
    if name.endswith('.lzma'):return lzma.compress(data,format=lzma.FORMAT_ALONE,preset=9)
    if name.endswith('.xz'):return lzma.compress(data,format=lzma.FORMAT_XZ,preset=9)
    if name.endswith('.gz'):return gzip.compress(data,compresslevel=9,mtime=0)
    raise ValueError('unsupported tar compression: '+name)

def entries(name,data):
    with tarfile.open(fileobj=io.BytesIO(tar_bytes(name,data))) as tar:
        out=[]
        for member in tar.getmembers():
            content=tar.extractfile(member).read() if member.isfile() else None
            out.append((member,content))
        return out

def signature(items):
    return [(m.name,m.type,m.mode,m.mtime,m.size,m.linkname,
             hashlib.sha256(content).hexdigest() if content is not None else None)
            for m,content in items]

def normalize(source,destination):
    raw=source.read_bytes();original=members(raw);out=bytearray(b'!<arch>\n');count=0
    for header,name,data in original:
        body=data
        if name.startswith(('data.tar.','control.tar.')):
            before=entries(name,data);buffer=io.BytesIO()
            with tarfile.open(fileobj=buffer,mode='w',format=tarfile.PAX_FORMAT) as tar:
                for member,content in before:
                    fixed=copy.copy(member);fixed.pax_headers=dict(member.pax_headers)
                    for key in ('uid','gid','uname','gname'):fixed.pax_headers.pop(key,None)
                    # Empty names make both dpkg and tar use numeric 0 on Linux and iOS.
                    fixed.uid=fixed.gid=0;fixed.uname=fixed.gname=''
                    tar.addfile(fixed,io.BytesIO(content) if content is not None else None)
            body=compress(name,buffer.getvalue());after=entries(name,body)
            assert signature(before)==signature(after),'payload content/structure changed'
            assert all(m.uid==0 and m.gid==0 for m,_ in after)
            count+=len(after)
        fixed_header=header[:16]+b'0'.ljust(12)+b'0'.ljust(6)+b'0'.ljust(6)+header[40:48]+str(len(body)).encode().ljust(10)+b'`\n'
        out.extend(fixed_header);out.extend(body)
        if len(body)&1:out.extend(b'\n')
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_bytes(out)
    return {'input':str(source),'input_sha256':hashlib.sha256(raw).hexdigest(),
            'output':str(destination),'sha256':hashlib.sha256(out).hexdigest(),'bytes':len(out),
            'normalized_entries':count,'file_bytes_modes_links_and_timestamps':'identical',
            'ownership':'numeric 0:0, empty owner/group names'}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=pathlib.Path);parser.add_argument('output',type=pathlib.Path)
    args=parser.parse_args();print(json.dumps(normalize(args.source,args.output),indent=2))
