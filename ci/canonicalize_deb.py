"""Canonicalize numeric archive ownership without running any package scripts."""
import hashlib,io,os,pathlib,subprocess,sys,tarfile,tempfile
package=pathlib.Path(sys.argv[1]).resolve()
def records(path):
 blob=subprocess.check_output(['dpkg-deb','--fsys-tarfile',str(path)])
 with tarfile.open(fileobj=io.BytesIO(blob)) as archive:
  result={}
  for m in archive:
   name=pathlib.PurePosixPath(m.name)
   if name.is_absolute() or '..' in name.parts or not (m.isfile() or m.isdir()):raise ValueError('Unsafe package record')
   result[str(name)]=(m.mode,hashlib.sha256(archive.extractfile(m).read()).hexdigest() if m.isfile() else None)
  return result
before=records(package)
with tempfile.TemporaryDirectory(prefix='qh-repack-',dir=package.parent,ignore_cleanup_errors=True) as d:
 root=pathlib.Path(d);stage=root/'stage';rebuilt=root/'package.deb'
 subprocess.run(['dpkg-deb','--raw-extract',str(package),str(stage)],check=True)
 # Some extraction hosts apply their private umask to intermediate directories.
 # Restore the verified source archive's modes explicitly before repacking.
 for name,(mode,digest) in before.items():os.chmod(stage/name,mode)
 helper=stage/'usr/libexec/quiethosts-helper'
 assert helper.stat().st_mode&0o7777==0o4755,'Lost setuid mode'
 subprocess.run(['dpkg-deb','--build','--root-owner-group','-Zxz',str(stage),str(rebuilt)],check=True)
 after=records(rebuilt)
 assert after==before, {k:(before.get(k),after.get(k)) for k in set(before)|set(after) if before.get(k)!=after.get(k)}
 os.replace(rebuilt,package)
print('Canonical numeric root ownership; all payload bytes and modes unchanged.')
