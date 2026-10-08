"""Portable regression models + actual fixed DNS runner against mock executables."""
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
def run(args):subprocess.run(args,cwd=root,check=True)
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
 # The theme control must remain Apple's native segmented control, with system
 # touch size and dynamic colors rather than a hand-drawn toggle.
 theme=ui.split('- (void)renderSettings {',1)[1].split('- (void)retryReload',1)[0]
 assert 'UISegmentedControl *theme' in theme
 assert 'theme.selectedSegmentTintColor = Accent()' in theme
 assert '[theme.heightAnchor constraintGreaterThanOrEqualToConstant:44]' in theme
 assert 'self.stack.spacing = 14' in ui and 'card.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16)' in ui
 home=ui.split('- (void)render {',1)[1].split('- (void)renderRules {',1)[0]
 assert 'QH_ADD_ACTION_ROW' in home and 'ActionSeparator()' in home
 assert 'Button(QHL(@"Apply draft"), YES' in home
 assert 'QHL(@"Draft is stored on this device. Apply it to update managed Hosts.")' in home
 assert 'This draft was saved to the helper in this session.' not in home
 module=(root/'Module/Resources/Info.plist').read_text()
 assert '<key>CFBundleSupportedPlatforms</key>' in module and '<string>iPhoneOS</string>' in module
 main=(root/'Helper/main.m').read_text()
 assert 'QHRunDNSReload(path, 15, &DNSChild)' in main
 assert 'setuid(' not in main.replace('No setuid(0)/setgid(0).','')
 print('Controller/delegate and fixed-runner integration source checks passed; UIKit/device behavior still unverified.')
