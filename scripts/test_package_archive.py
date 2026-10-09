"""Actual dpkg archive roundtrips; never execute maintainer scripts."""
from pathlib import Path
import io, json, os, subprocess, sys, tarfile, tempfile
ROOT=Path(__file__).resolve().parents[1]
checks=0
def run(args,success=True):
    global checks
    done=subprocess.run(args,cwd=ROOT,capture_output=True,text=True)
    checks+=1
    assert (done.returncode==0)==success,(args,done.stdout,done.stderr)
    return done

def records(deb):
    out={}
    for flag in ('--fsys-tarfile','--ctrl-tarfile'):
        blob=subprocess.check_output(['dpkg-deb',flag,str(deb)])
        with tarfile.open(fileobj=io.BytesIO(blob)) as tar:
            out[flag]=[(m.name,m.mode,m.uid,m.gid,tar.extractfile(m).read() if m.isfile() else None) for m in tar]
    return out

def build(folder,scheme,mode=0o4755,wrong_prefix=False):
    stage=folder/'stage';(stage/'DEBIAN').mkdir(parents=True)
    control=(ROOT/'control').read_text()
    if scheme=='rootless':control=control.replace('Architecture: iphoneos-arm64e','Architecture: iphoneos-arm64')
    (stage/'DEBIAN/control').write_text(control)
    layout=ROOT/('layout-rootless' if scheme=='rootless' else 'layout')/'DEBIAN'
    for name in ('postinst','prerm','postrm'):
        p=stage/'DEBIAN'/name;p.write_bytes((layout/name).read_bytes());p.chmod(0o755)
    prefix='var/jb/' if scheme=='rootless' and not wrong_prefix else ''
    helper=stage/(prefix+'usr/libexec/quiethosts-helper');helper.parent.mkdir(parents=True)
    helper.write_bytes(b'fixture-not-executable\0');helper.chmod(mode)
    package=folder/'package.deb'
    run(['dpkg-deb','--build','--root-owner-group',str(stage),str(package)])
    return package

def main():
    results=[]
    for scheme in ('roothide','rootless'):
        with tempfile.TemporaryDirectory(prefix='qh-repack-test-') as temp:
            folder=Path(temp);deb=build(folder,scheme);before=records(deb)
            run([sys.executable,'ci/canonicalize_deb.py',str(deb),'--scheme',scheme])
            after=records(deb)
            assert after==before,'payload/control bytes, modes or numeric owners changed'
            run([sys.executable,'scripts/check_package_ownership.py',str(deb),'--scheme',scheme])
            for bad,mode,wrong in [('bad-mode',0o755,False),('wrong-prefix',0o4755,True)]:
                if scheme=='roothide' and wrong:continue
                sub=folder/bad;sub.mkdir();broken=build(sub,scheme,mode,wrong)
                raw=broken.read_bytes()
                run([sys.executable,'ci/canonicalize_deb.py',str(broken),'--scheme',scheme],False)
                assert broken.read_bytes()==raw,'failure changed original archive'
                run([sys.executable,'scripts/check_package_ownership.py',str(broken),'--scheme',scheme],False)
            other='rootless' if scheme=='roothide' else 'roothide'
            run([sys.executable,'ci/canonicalize_deb.py',str(deb),'--scheme',other],False)
            run([sys.executable,'scripts/check_package_ownership.py',str(deb),'--scheme',other],False)
            results.append({'scheme':scheme,'roundtrip':'data/control bytes/modes and uid/gid identical',
                            'negative':'wrong mode/prefix/scheme rejected, original archive unchanged'})
    assert checks>=15
    print(json.dumps({'checks':checks,'results':results,'scripts_executed':False},indent=2))
if __name__=='__main__':main()
