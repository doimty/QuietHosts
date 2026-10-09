#!/usr/bin/env python3
"""Isolated package/maintainer fixtures. Synthetic Mach-O, NOT Apple builds."""
from pathlib import Path
import json, os, plistlib, struct, subprocess, sys, tempfile
import validate
ROOT=Path(__file__).resolve().parents[1]
checks=0
def check(value, reason):
    global checks
    checks+=1
    assert value, reason

def binary(arch, minimum=0xF0000, deps=(), signed=True, rpaths=None):
    commands=[struct.pack('<6I',0x32,24,2,minimum,0x100500,0)]
    if signed:commands.append(struct.pack('<4I',0x1d,16,0,1))
    if rpaths is None:
        rpaths=['/var/jb/usr/lib','@loader_path/.jbroot/usr/lib'] if arch=='rootless' else []
    for name in rpaths:
        data=name.encode()+b'\0';size=(12+len(data)+7)//8*8
        commands.append(struct.pack('<3I',0x8000001c,size,12)+data+b'\0'*(size-12-len(data)))
    for name in deps:
        data=name.encode()+b'\0'
        size=(24+len(data)+7)//8*8
        commands.append(struct.pack('<6I',0xc,size,24,0,0,0)+data+b'\0'*(size-24-len(data)))
    blob=b''.join(commands)
    return struct.pack('<8I',0xfeedfacf,0x100000c,2 if arch=='roothide' else 0,2,len(commands),len(blob),0,0)+blob

def gate(stage, scheme, success=True, reason=None):
    result=subprocess.run([sys.executable,str(ROOT/'scripts/validate.py'),
        '--stage',str(stage),'--scheme',scheme],capture_output=True,text=True)
    log=result.stdout+result.stderr
    check((result.returncode==0)==success, log)
    if not success and reason:check(reason in log, log)
    return log

def fixture(stage, scheme):
    payload=stage/'var/jb' if scheme=='rootless' else stage
    app=payload/'Applications/QuietHosts.app'
    helper=payload/'usr/libexec/quiethosts-helper'
    helper.parent.mkdir(parents=True)
    app.mkdir(parents=True)
    (app/'QuietHosts').write_bytes(binary(scheme))
    helper.write_bytes(binary(scheme));helper.chmod(0o4755)
    (app/'Info.plist').write_bytes((ROOT/'App/Resources/Info.plist').read_bytes())
    layout=ROOT/('layout-rootless' if scheme=='rootless' else 'layout')/'DEBIAN'
    (stage/'DEBIAN').mkdir()
    control=(ROOT/'control').read_text()
    if scheme=='rootless':control=control.replace('Architecture: iphoneos-arm64e','Architecture: iphoneos-arm64')
    (stage/'DEBIAN/control').write_text(control)
    for name in ('postinst','prerm','postrm'):
        (stage/'DEBIAN'/name).write_bytes((layout/name).read_bytes())
    for name in ('Icon1024.png','Icon60@3x.png','Icon60@2x.png'):
        (app/name).write_bytes((ROOT/'App/Resources'/name).read_bytes())
    for locale in ('en','zh-Hans'):
        folder=app/(locale+'.lproj');folder.mkdir()
        (folder/'Localizable.strings').write_bytes((ROOT/'App/Resources'/(locale+'.lproj')/'Localizable.strings').read_bytes())
    return app,helper

def replace_text(path,old,new):
    text=path.read_text();check(old in text,'missing mutation anchor '+old)
    path.write_text(text.replace(old,new))

def change_info(app,key,value):
    info=plistlib.loads((app/'Info.plist').read_bytes());info[key]=value
    (app/'Info.plist').write_bytes(plistlib.dumps(info))

def main():
    results=[]
    def case(scheme,name,mutation=None,reason=None):
        with tempfile.TemporaryDirectory(prefix='qh-package-fixture-') as temp:
            stage=Path(temp);app,helper=fixture(stage,scheme)
            if mutation:mutation(stage,app,helper)
            gate(stage,scheme,mutation is None,reason)
            results.append({'scheme':scheme,'case':name,'result':'accepted' if mutation is None else 'rejected'})
    for scheme in ('roothide','rootless'):
        other='rootless' if scheme=='roothide' else 'roothide'
        case(scheme,'valid package')
        case(scheme,'wrong App CPU',lambda s,a,h:(a/'QuietHosts').write_bytes(binary(other)),'Wrong CPU architecture')
        case(scheme,'wrong helper CPU',lambda s,a,h:h.write_bytes(binary(other)),'Wrong CPU architecture')
        case(scheme,'missing setuid',lambda s,a,h:h.chmod(0o0755),'Helper not setuid')
        case(scheme,'wrong minOS',lambda s,a,h:(a/'QuietHosts').write_bytes(binary(scheme,minimum=0x100000)),'Missing minOS/signature')
        case(scheme,'missing signature',lambda s,a,h:(a/'QuietHosts').write_bytes(binary(scheme,signed=False)),'Missing minOS/signature')
        case(scheme,'App build mismatch',lambda s,a,h:change_info(a,'CFBundleVersion','12'),'Staged App metadata mismatch')
        case(scheme,'package version mismatch',lambda s,a,h:replace_text(s/'DEBIAN/control','native13','native12'),'Staged package metadata mismatch')
        case(scheme,'control architecture mismatch',lambda s,a,h:replace_text(s/'DEBIAN/control','iphoneos-arm64' if scheme=='rootless' else 'iphoneos-arm64e','iphoneos-arm64e' if scheme=='rootless' else 'iphoneos-arm64'),'Staged package metadata mismatch')
        case(scheme,'dependency mismatch',lambda s,a,h:replace_text(s/'DEBIAN/control','com.ps.letmeblock','wrong.dependency'),'Staged package metadata mismatch')
        case(scheme,'maintainer path mismatch',lambda s,a,h:replace_text(s/'DEBIAN/prerm','quiethosts-helper','wrong-helper'),'Maintainer script mismatch')
        case(scheme,'compat library',lambda s,a,h:h.write_bytes(binary(scheme,deps=['/Library/AutoPatches/bad.dylib'])),'Wrong platform or compatibility library found')
        case(scheme,'unexpected payload',lambda s,a,h:(s/'extra.conf').write_text('bad'),'Unexpected payload')
    case('rootless','wrong install prefix',lambda s,a,h:(s/'var/jb/Applications').rename(s/'Applications'),'No such file')
    case('rootless','RootHide linked library',lambda s,a,h:h.write_bytes(binary('rootless',deps=['@loader_path/.jbroot/usr/lib/libroothide.dylib'])),'Wrong platform or compatibility library found')
    case('rootless','missing rootless rpath',lambda s,a,h:h.write_bytes(binary('rootless',rpaths=[])),'Rootless rpath missing')
    # Valid v2 @loader_path/.jbroot is a rootless rpath, not a forbidden shim.
    case('rootless','rootless v2 rpath accepted')
    check(checks>30 and len(results)>25,'empty or incomplete fixture suite')
    print(json.dumps({'scope':'synthetic Mach-O + real validation execution; NOT Apple binary/signature proof',
                      'checks':checks,'cases':results},indent=2))

if __name__=='__main__':main()
