"""Check tar numeric ownership instead of trusting human-readable owner names."""
import argparse,io,pathlib,subprocess,sys,tarfile
parser=argparse.ArgumentParser();parser.add_argument('package',type=pathlib.Path);parser.add_argument('--scheme',choices=('roothide','rootless'),default='roothide');args=parser.parse_args()
p=args.package;count=0;helpers=0
expected='var/jb/usr/libexec/quiethosts-helper' if args.scheme=='rootless' else 'usr/libexec/quiethosts-helper'
architecture='iphoneos-arm64' if args.scheme=='rootless' else 'iphoneos-arm64e'
assert subprocess.check_output(['dpkg-deb','-f',str(p),'Architecture'],text=True).strip()==architecture,'Wrong package architecture'
for flag in ('--ctrl-tarfile','--fsys-tarfile'):
 with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['dpkg-deb',flag,str(p)]))) as archive:
  for m in archive:
   assert m.uid==0 and m.gid==0,(m.name,m.uid,m.gid)
   assert not pathlib.PurePosixPath(m.name).is_absolute() and '..' not in pathlib.PurePosixPath(m.name).parts
   assert m.isfile() or m.isdir(),m.name
   name=str(pathlib.PurePosixPath(m.name))
   if name.endswith('usr/libexec/quiethosts-helper'):
    assert flag=='--fsys-tarfile' and name==expected,'Wrong-prefix helper'
    assert m.isfile() and m.mode==0o4755,'Helper setuid lost'
    helpers+=1
   count+=1
assert helpers==1,'Missing or duplicate helper'
print(f'Numeric ownership and path checks passed for {count} archive records.')
