"""Portable regression models + actual fixed DNS runner against mock executables."""
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
def run(args):subprocess.run(args,cwd=root,check=True)
run(['python3', 'scripts/test_ui_palette.py'])
run(['python3', 'scripts/test_native10_ui.py'])
with tempfile.TemporaryDirectory(prefix='qh-regressions-') as folder:
 d=Path(folder)
 flags=['clang','-std=c11','-D_DEFAULT_SOURCE','-D_DARWIN_C_SOURCE','-Wall','-Wextra','-Werror','-pedantic']
 picker=d/'picker';dns=d/'dns'
 run([*flags,'Tests/ImportLifecycleTests.c','-o',str(picker)])
 run([str(picker)])
 run([*flags,'Helper/QHDNSReload.c','Tests/DNSReloadTests.c','-o',str(dns)])
 run([str(dns),'--ordinary'])
 if os.environ.get('GITHUB_ACTIONS')=='true':run(['sudo','-n',str(dns),'--privileged'])
 elif os.geteuid()==0:run([str(dns),'--privileged'])
 else:print('Privileged mock-UID fixtures deferred to CI (no sudo requested locally).')
 # Integration checks supplement the model. They are not UIKit runtime tests.
 ui=(root/'App/QHAppController.m').read_text()
 assert 'UIAdaptivePresentationControllerDelegate' in ui
 assert 'picker.presentationController.delegate = self' in ui
 method=ui.split('- (void)presentationControllerDidDismiss:',1)[1].split('- (void)documentPicker:',1)[0]
 assert 'cancelFilePicker:' in method and 'finishBusy' not in method
 cancel=ui.split('- (void)cancelFilePicker:',1)[1].split('- (void)documentPickerWasCancelled:',1)[0]
 assert 'QHImportCancel' in cancel and 'finishBusy' in cancel and 'pickingAllowlist = NO' in cancel
 select=ui.split('- (void)documentPicker:',1)[1].split('- (void)editText:',1)[0]
 assert 'QHImportSelect' in select and 'QHImportFinishRead' in select
 # Native9 replaces the inline segmented control and separate source cards with
 # native selection/list/detail components. Keep behavior gates in the dedicated
 # structural/frozen-scope suite, plus execute actual UIKit fixtures in CI.
 run(['python3', 'scripts/test_native9_ui.py'])
 assert 'self.stack.spacing = 14' in ui
 build=(root/'Makefile').read_text()
 assert 'SUBPROJECTS = App Helper' in build and 'CCSupport' not in build
 assert not (root/'Module').exists()
 assert 'CCSupport' not in ui
 main=(root/'Helper/main.m').read_text()
 assert 'QHRunDNSReload(path, 15, &DNSChild)' in main
 assert 'setuid(' not in main.replace('No setuid(0)/setgid(0).','')
 print('Controller/delegate and fixed-runner integration source checks passed; UIKit/device behavior still unverified.')
