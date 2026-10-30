"""Run only on disposable macOS CI. Simulator mock Bridge; no device/helper commands."""
from pathlib import Path
import json, os, plistlib, shutil, subprocess, tempfile, threading
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build-metadata';OUT.mkdir(exist_ok=True)
def run(*args):
    subprocess.run(args,check=True,cwd=ROOT)
def read(*args):
    return subprocess.check_output(args,cwd=ROOT,text=True)
def harvest_partial_evidence(container):
    errors=[]
    for file in (container/'Documents').glob('*'):
        if file.is_file() and not file.is_symlink() and file.suffix in ('.json','.png','.txt','.log'):
            try:shutil.copyfile(file,OUT/('visual-'+file.name))
            except OSError as error:errors.append({'file':file.name,'error':str(error)})
    if errors:(OUT/'visual-harvest-errors.json').write_text(json.dumps(errors,indent=2))
def sample_owned_ui_fixture():
    # Host-side diagnostics for only this disposable simulator executable.
    # Never sample a device/helper or a different application process.
    info={'scope':'owned QHVisualSmoke timeout diagnostics only','pids':[]}
    try:
        found=subprocess.run(['pgrep','-x','QHVisualSmoke'],capture_output=True,text=True,timeout=10)
        pids=[line.strip() for line in found.stdout.splitlines() if line.strip().isdigit()]
        info['pids']=pids
        if len(pids)==1:
            sampled=subprocess.run(['sample',pids[0],'3','1','-file',str(OUT/'visual-timeout-sample.txt')],capture_output=True,text=True,timeout=20)
            info['sample_returncode']=sampled.returncode
            info['diagnostic']=sampled.stdout+'\n'+sampled.stderr
        else:info['diagnostic']='No unique owned UI fixture PID was available.'
    except Exception as error:info['diagnostic']=str(error)
    (OUT/'visual-timeout-process.json').write_text(json.dumps(info,indent=2))
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
    sources=['Tests/VisualSmoke.m','Tests/DialogSmoke.m','App/QHDialogController.m','App/QHAppController.m','App/QHVisualComponents.m','App/QHStore.m','App/QHDownload.m','Shared/QHRuleEngine.m','Shared/QHStatusPresentation.m','Shared/QHParser.c']
    run('xcrun','--sdk','iphonesimulator','clang','-isysroot',sdk,'-arch',arch,'-mios-simulator-version-min=15.0','-fobjc-arc','-fblocks','-DQH_TESTING=1','-D_DARWIN_C_SOURCE','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Werror=unguarded-availability','-framework','UIKit','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics','-framework','UniformTypeIdentifiers',*sources,'-o',str(app/'QHVisualSmoke'))
    run('codesign','--force','--sign','-',str(app))
    devices=json.loads(read('xcrun','simctl','list','devices','available','--json'))['devices']
    candidates=[dict(d,runtime=runtime) for runtime,ds in devices.items() if 'iOS' in runtime for d in ds if d.get('isAvailable') and 'iPhone' in d['name']]
    if not candidates:raise SystemExit('No available iPhone simulator: smoke cannot be counted as pass.')
    identifier=candidates[0]['udid']
    (OUT/'visual-environment.json').write_text(json.dumps({'device':candidates[0],'host_arch':arch,'sdk':sdk,'scope':'disposable simulator, not target device'},indent=2))
    help_output=subprocess.run(['xcrun','simctl','help','launch'],capture_output=True,text=True,timeout=30)
    (OUT/'visual-launch-help.txt').write_text(help_output.stdout+'\n'+help_output.stderr)
    if candidates[0]['state']!='Booted':run('xcrun','simctl','boot',identifier)
    run('xcrun','simctl','bootstatus',identifier,'-b')
    run('xcrun','simctl','install',identifier,str(app))
    container=Path(read('xcrun','simctl','get_app_container',identifier,info['CFBundleIdentifier'],'data').strip())
    marker=container/'Documents/software-keyboard-ready.flag'
    captured=container/'Documents/software-keyboard-captured.flag'
    capture_failed=container/'Documents/software-keyboard-capture-failed.flag'
    for flag in (marker,captured,capture_failed):
        if flag.exists():flag.unlink()
    # A loaded runner can take well over 20s for one shot, and `simctl io
    # screenshot` can also hang outright. Attempts are precise-killed on
    # timeout; the app side bound is 120s and exits at once on this failure
    # marker, so a stuck driver ends the run with a precise message.
    shot_timeout=float(os.environ.get('QH_KEYBOARD_SHOT_TIMEOUT','45'))
    shot_attempts=int(os.environ.get('QH_KEYBOARD_SHOT_ATTEMPTS','3'))
    stop=threading.Event();capture_errors=[]
    def capture_keyboard():
        while not stop.wait(.1):
            if marker.exists():
                for attempt in range(1,shot_attempts+1):
                    try:
                        subprocess.run(['xcrun','simctl','io',identifier,'screenshot',str(OUT/'visual-software-keyboard-screen.png')],check=True,timeout=shot_timeout,capture_output=True)
                        captured.write_text('captured while first responder held; attempt %d' % attempt)
                        return
                    except Exception as error:
                        capture_errors.append('attempt %d: %s' % (attempt,error))
                capture_failed.write_text('\n'.join(capture_errors))
                return
    capture=threading.Thread(target=capture_keyboard,daemon=True);capture.start()
    try:
        # A cold simulator boot on a loaded runner has consumed 4-5 minutes
        # before the app's first smoke log; the app-side flow itself needs
        # another ~2 minutes. 300s killed healthy runs mid-dialog, so budget
        # 600s here (the job cap is widened to match).
        launch=subprocess.run(['xcrun','simctl','launch','--console',identifier,info['CFBundleIdentifier'],'-AppleLanguages','(zh-Hans)','-AppleLocale','zh_CN'],cwd=ROOT,capture_output=True,text=True,timeout=600)
    except subprocess.TimeoutExpired as error:
        def text(value):return value.decode(errors='replace') if isinstance(value,bytes) else (value or '')
        logs=text(error.stdout)+'\n'+text(error.stderr)
        (OUT/'visual-smoke-console.txt').write_text(logs)
        print(logs,flush=True)
        sample_owned_ui_fixture()
        raise
    finally:
        stop.set();capture.join(timeout=25)
        # A failed/timeout launch must retain the last progress, partial PNGs,
        # JSON and diagnostic files. Missing result still fails the gates below.
        harvest_partial_evidence(container)
    logs=launch.stdout+'\n'+launch.stderr
    (OUT/'visual-smoke-console.txt').write_text(logs)
    print(logs)
    report=json.loads((OUT/'visual-result.json').read_text())
    assert launch.returncode==0 and report['failures']==0 and report['writes']==0,report
    assert not capture_errors and (OUT/'visual-software-keyboard-screen.png').is_file(), ('Complete keyboard screenshot missing',capture_errors)
    assert report['checks']>100 and report['dialog_checks']>=90 and report['mock_status_requests']>0,report
    assert report['downloads']==0, 'UI fixtures must never make network downloads'
    assert report['component_fixtures']==18 and report['controller_cases']==108, report
    assert report['controller_live_transitions']==18 and report['native_switch_checks']>=270, report
    assert report['consent_cancellations']==5 and report['screenshots']==10, report
    assert 'Unable to simultaneously satisfy constraints' not in logs, 'UIKit constraint conflict'
    print('UIKit simulator smoke PASS:',report)
