"""Canonicalize numeric archive ownership without running any package scripts."""
import argparse,hashlib,io,os,pathlib,subprocess,sys,tarfile,tempfile
parser=argparse.ArgumentParser();parser.add_argument('package',type=pathlib.Path);parser.add_argument('--scheme',choices=('roothide','rootless'),default='roothide');args=parser.parse_args()
package=args.package.resolve()
architecture='iphoneos-arm64' if args.scheme=='rootless' else 'iphoneos-arm64e'
assert subprocess.check_output(['dpkg-deb','-f',str(package),'Architecture'],text=True).strip()==architecture,'Wrong package architecture for scheme'
helper_path='var/jb/usr/libexec/quiethosts-helper' if args.scheme=='rootless' else 'usr/libexec/quiethosts-helper'
def records(path,flag='--fsys-tarfile'):
 blob=subprocess.check_output(['dpkg-deb',flag,str(path)])
 with tarfile.open(fileobj=io.BytesIO(blob)) as archive:
  result={}
  for m in archive:
   name=pathlib.PurePosixPath(m.name)
   if name.is_absolute() or '..' in name.parts or not (m.isfile() or m.isdir()):raise ValueError('Unsafe package record')
   result[str(name)]=(m.mode,hashlib.sha256(archive.extractfile(m).read()).hexdigest() if m.isfile() else None)
  return result
before=records(package);control_before=records(package,'--ctrl-tarfile')
assert helper_path in before,'Missing scheme helper'
assert not any(p.endswith('usr/libexec/quiethosts-helper') and p!=helper_path for p in before),'Wrong-prefix helper'
with tempfile.TemporaryDirectory(prefix='qh-repack-',dir=package.parent,ignore_cleanup_errors=True) as d:
 root=pathlib.Path(d);stage=root/'stage';rebuilt=root/'package.deb'
 subprocess.run(['dpkg-deb','--raw-extract',str(package),str(stage)],check=True)
 # Some extraction hosts apply their private umask to intermediate directories.
 # Restore the verified source archive's modes explicitly before repacking.
 for name,(mode,digest) in before.items():os.chmod(stage/name,mode)
 for name,(mode,digest) in control_before.items():os.chmod(stage/'DEBIAN'/name,mode)
 helper=stage/helper_path
 assert helper.stat().st_mode&0o7777==0o4755,'Lost setuid mode'
 subprocess.run(['dpkg-deb','--build','--root-owner-group','-Zxz',str(stage),str(rebuilt)],check=True)
 after=records(rebuilt)
 assert records(rebuilt,'--ctrl-tarfile')==control_before,'Control payload changed'
 assert after==before, {k:(before.get(k),after.get(k)) for k in set(before)|set(after) if before.get(k)!=after.get(k)}
 os.replace(rebuilt,package)
print('Canonical numeric root ownership; all payload bytes and modes unchanged.')
