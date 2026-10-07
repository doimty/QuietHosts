"""Check tar numeric ownership instead of trusting human-readable owner names."""
import io,pathlib,subprocess,sys,tarfile
p=pathlib.Path(sys.argv[1]);count=0
for flag in ('--ctrl-tarfile','--fsys-tarfile'):
 with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['dpkg-deb',flag,str(p)]))) as archive:
  for m in archive:
   assert m.uid==0 and m.gid==0,(m.name,m.uid,m.gid)
   assert not pathlib.PurePosixPath(m.name).is_absolute() and '..' not in pathlib.PurePosixPath(m.name).parts
   assert m.isfile() or m.isdir(),m.name
   if m.name.lstrip('./')=='usr/libexec/quiethosts-helper':assert m.mode==0o4755
   count+=1
print(f'Numeric ownership and path checks passed for {count} archive records.')
