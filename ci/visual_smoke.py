"""Run only on disposable macOS CI. Simulator mock Bridge; no device/helper commands."""
from pathlib import Path
import json, os, plistlib, shutil, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build-metadata';OUT.mkdir(exist_ok=True)
def run(*args):
    subprocess.run(args,check=True,cwd=ROOT)
def read(*args):
    return subprocess.check_output(args,cwd=ROOT,text=True)
if os.environ.get('GITHUB_ACTIONS')!='true':
    raise SystemExit('Visual smoke is restricted to disposable GitHub Actions macOS CI.')
with tempfile.TemporaryDirectory(prefix='qh-visual-') as folder:
    work=Path(folder);app=work/'QHVisualSmoke.app';app.mkdir()
    info={'CFBundleIdentifier':'com.doimty.qhvisualsmoke','CFBundleExecutable':'QHVisualSmoke','CFBundleName':'QHVisualSmoke','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','MinimumOSVersion':'15.0','CFBundleSupportedPlatforms':['iPhoneSimulator'],'CFBundleDevelopmentRegion':'en','CFBundleLocalizations':['en','zh-Hans'],'UIDeviceFamily':[1],'LSRequiresIPhoneOS':True,'UILaunchScreen':{}}
    (app/'Info.plist').write_bytes(plistlib.dumps(info))
    for locale in ('en','zh-Hans'):
        shutil.copytree(ROOT/'App/Resources'/f'{locale}.lproj',app/f'{locale}.lproj')
    sdk=read('xcrun','--sdk','iphonesimulator','--show-sdk-path').strip()
    arch=read('uname','-m').strip()
    sources=['Tests/VisualSmoke.m','App/QHAppController.m','App/QHVisualComponents.m','App/QHStore.m','App/QHDownload.m','Shared/QHRuleEngine.m','Shared/QHStatusPresentation.m','Shared/QHParser.c']
    run('xcrun','--sdk','iphonesimulator','clang','-isysroot',sdk,'-arch',arch,'-mios-simulator-version-min=15.0','-fobjc-arc','-fblocks','-DQH_TESTING=1','-D_DARWIN_C_SOURCE','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Werror=unguarded-availability','-framework','UIKit','-framework','Foundation','-framework','UniformTypeIdentifiers',*sources,'-o',str(app/'QHVisualSmoke'))
    run('codesign','--force','--sign','-',str(app))
    devices=json.loads(read('xcrun','simctl','list','devices','available','--json'))['devices']
    candidates=[d for runtime,ds in devices.items() if 'iOS' in runtime for d in ds if d.get('isAvailable') and 'iPhone' in d['name']]
    if not candidates:raise SystemExit('No available iPhone simulator: smoke cannot be counted as pass.')
    identifier=candidates[0]['udid']
    if candidates[0]['state']!='Booted':run('xcrun','simctl','boot',identifier)
    run('xcrun','simctl','bootstatus',identifier,'-b')
    run('xcrun','simctl','install',identifier,str(app))
    launch=subprocess.run(['xcrun','simctl','launch','--console',identifier,info['CFBundleIdentifier']],cwd=ROOT,capture_output=True,text=True,timeout=150)
    logs=launch.stdout+'\n'+launch.stderr
    (OUT/'visual-smoke-console.txt').write_text(logs)
    print(logs)
    container=Path(read('xcrun','simctl','get_app_container',identifier,info['CFBundleIdentifier'],'data').strip())
    for file in (container/'Documents').glob('*'):
        if file.suffix in ('.json','.png'):shutil.copyfile(file,OUT/('visual-'+file.name))
    report=json.loads((OUT/'visual-result.json').read_text())
    assert launch.returncode==0 and report['failures']==0 and report['writes']==0,report
    assert report['checks']>100 and report['mock_status_requests']>0,report
    assert 'Unable to simultaneously satisfy constraints' not in logs, 'UIKit constraint conflict'
    print('UIKit simulator smoke PASS:',report)
