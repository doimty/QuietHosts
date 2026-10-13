"""Native10 source/icon contracts. Actual UIKit lifecycle tests run only on CI."""
from pathlib import Path
import struct,zlib
ROOT=Path(__file__).resolve().parents[1]

def check(dialog,controller):
    assert '[UIAlertController' not in controller and '[UIAlertAction' not in controller
    assert controller.count('dialogControllerWithTitle:')==7
    assert controller.count('QHConfigureModal(nav);')==2
    assert 'modalPresentationStyle=UIModalPresentationFormSheet' in dialog
    assert 'controller.modalInPresentation=YES' in dialog
    assert 'sheet.prefersGrabberVisible=YES' in dialog
    assert 'sheet.preferredCornerRadius=28;' in dialog
    assert 'view.keyboardLayoutGuide.topAnchor' in dialog
    assert 'sheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierLarge;' in dialog
    assert '- (BOOL)usesCenteredConfirmation' in dialog
    assert 'UIModalPresentationOverFullScreen' in dialog
    assert 'UIModalTransitionStyleCrossDissolve' in dialog
    assert '[self buildCenteredConfirmation];' in dialog
    assert 'self.centeredCard=card;' in dialog
    assert '[self setNavigationBarHidden:YES animated:NO];' in dialog
    assert 'holder.layer.cornerRadius=12;' in dialog
    assert 'field.borderStyle=UITextBorderStyleNone' in dialog
    fields=dialog.split('for (UITextField *field in self.mutableFields)',1)[1].split('__weak typeof(self) weak=self;',1)[0]
    assert 'field.translatesAutoresizingMaskIntoConstraints=NO;' in fields
    assert fields.index('field.translatesAutoresizingMaskIntoConstraints=NO;') < fields.index('[holder addSubview:field];')
    assert 'CGAffineTransformMakeScale' not in dialog and 'usingSpringWithDamping' not in dialog
    assert '- (UIModalPresentationStyle)modalPresentationStyle' not in dialog, 'Use actual UIKit setter, not a dynamic getter'
    assert '- (UIModalTransitionStyle)modalTransitionStyle' not in dialog
    configure=dialog.split('void QHConfigureModal(',1)[1].split('@interface QHDialogAction',1)[0]
    assert 'controller.modalPresentationStyle=centered ? UIModalPresentationOverFullScreen' in configure
    assert 'controller.modalTransitionStyle=centered ? UIModalTransitionStyleCrossDissolve' in configure
    assert 'if (!centered) {' in configure
    assert configure.index('if (!centered) {') < configure.index('controller.sheetPresentationController')
    actions=dialog.split('- (void)addAction:',1)[1].split('- (void)addTextFieldWithConfigurationHandler:',1)[0]
    add_fields=dialog.split('- (void)addTextFieldWithConfigurationHandler:',1)[1].split('- (void)buildCenteredConfirmation',1)[0]
    assert 'QHConfigureModal(self);' in actions and 'QHConfigureModal(self);' in add_fields
    appearance=dialog.split('- (void)viewWillAppear:',1)[1]
    assert 'QHConfigureModal(self)' not in appearance, 'Do not switch modal properties during entry'
    assert '[canvas addSubview:card];' in dialog
    assert '[root addSubview:scroll];' in dialog
    assert '[scroll addSubview:canvas];' in dialog
    assert 'UIButtonConfiguration.plainButtonConfiguration' in dialog
    assert 'constant:22' not in controller, 'editor insets must match the shared 18pt rhythm'
    assert 'UIFontTextStyleSubheadline' not in controller.split('static UIButton *Button(',1)[1].split('static NSString *Number(',1)[0]
    assert 'initWithCustomView:Button(QHL(@"Cancel")' in controller
    assert controller.index('sampleCard]') < controller.index('Button(button, YES, YES, ^{')
    components=(ROOT/'App/QHVisualComponents.m').read_text()
    row=components.split('UIControl *QHVRow(',1)[1].split('static UIView *VStat(',1)[0]
    assert 'accessibilityHint' not in row, 'row subtitle must not be announced as a hint'
    assert 'QHCenteredConfirmationFor(' in dialog
    assert 'NSCharacterSet.newlineCharacterSet' in dialog
    handler=dialog.split('- (void)chooseAction:',1)[1].split('- (void)viewWillAppear:',1)[0]
    for required in ('if (self.resolving', 'self.resolving=YES', 'self.view.userInteractionEnabled=NO',
        'QHDialogController *keepAlive=self', 'completion:^{', 'if (action.handler) action.handler(action)', 'keepAlive.mutableActions=nil'):
        assert required in handler, required
    assert handler.index('dismissViewControllerAnimated') < handler.index('action.handler(action)')
    assert 'UIAlertActionStyleCancel' in dialog and 'UIAlertActionStyleDestructive' in dialog
    assert 'DColor(0xb42336,0xff8995)' in dialog
    assert 'DColor(0xffffff,0x13131a)' in dialog
    assert 'NSAssert(!self.contentBuilt' in dialog
    assert '- (void)viewDidLoad' not in dialog
    assert 'if (self.contentBuilt) return;' in dialog
    assert 'readwrite' not in (ROOT/'App/QHDialogController.h').read_text()
    handler=dialog.split('- (void)chooseAction:',1)[1].split('- (void)viewWillAppear:',1)[0]
    for required in ('if (self.resolving', 'self.resolving=YES', 'self.view.userInteractionEnabled=NO',
        'QHDialogController *keepAlive=self', 'completion:^{', 'if (action.handler) action.handler(action)', 'keepAlive.mutableActions=nil'):
        assert required in handler, required
    assert handler.index('dismissViewControllerAnimated') < handler.index('action.handler(action)')
    assert 'UIAlertActionStyleCancel' in dialog and 'UIAlertActionStyleDestructive' in dialog
    assert 'DColor(0xb42336,0xff8995)' in dialog
    assert 'DColor(0xffffff,0x13131a)' in dialog
    assert 'NSAssert(!self.contentBuilt' in dialog
    assert '- (void)viewDidLoad' not in dialog
    assert 'if (self.contentBuilt) return;' in dialog
    assert 'self.contentBuilt=YES;' in dialog
    assert 'readwrite' not in (ROOT/'App/QHDialogController.h').read_text()


def check_icon(path,size):
    raw=path.read_bytes();assert raw[:8]==b'\x89PNG\r\n\x1a\n'
    pos=8;has_data=False
    while pos<len(raw):
        length=struct.unpack_from('>I',raw,pos)[0];kind=raw[pos+4:pos+8];data=raw[pos+8:pos+8+length]
        assert zlib.crc32(kind+data)&0xffffffff==struct.unpack_from('>I',raw,pos+8+length)[0]
        if kind==b'IHDR':
            width,height,depth,color,*_=struct.unpack('>IIBBBBB',data)
            assert (width,height,depth,color)==(size,size,8,2), 'Expected opaque 8bit RGB icon'
        if kind==b'tRNS':raise AssertionError('Transparent icon')
        if kind==b'IDAT':has_data=True
        pos+=12+length
    assert has_data

def main():
    dialog=(ROOT/'App/QHDialogController.m').read_text();controller=(ROOT/'App/QHAppController.m').read_text()
    check(dialog,controller)
    mutations=[('self.resolving=YES','self.resolving=NO'),
        ('QHDialogController *keepAlive=self','QHDialogController *keepAlive=nil'),
        ('controller.modalInPresentation=YES','controller.modalInPresentation=NO'),
        ('sheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierLarge;','sheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierMedium;'),
        ('UIModalPresentationOverFullScreen','UIModalPresentationPageSheet'),
        ('[self buildCenteredConfirmation];',''),
        ('field.translatesAutoresizingMaskIntoConstraints=NO;',''),
        ('self.centeredCard=card;','self.centeredCard=card; card.transform=CGAffineTransformMakeScale(1.08,1.08);'),
        ('QHConfigureModal(self);',''),
        ('controller.modalPresentationStyle=centered ? UIModalPresentationOverFullScreen','controller.modalPresentationStyle=centered ? UIModalPresentationFormSheet'),
        ('    if (!centered) {\n        UISheetPresentationController *sheet=', '    {\n        UISheetPresentationController *sheet='),
        ('    [super viewWillAppear:animated];','    [super viewWillAppear:animated]; QHConfigureModal(self);')]
    for old,new in mutations:
        changed=dialog.replace(old,new);assert changed!=dialog
        try:check(changed,controller)
        except AssertionError:pass
        else:raise AssertionError('Unsafe mutation accepted: '+old)
    for name,size in [('Icon1024.png',1024),('Icon60@3x.png',180),('Icon60@2x.png',120)]:check_icon(ROOT/'App/Resources'/name,size)
    assert 'QHDialogController.m' in (ROOT/'App/Makefile').read_text()
    smoke=(ROOT/'Tests/DialogSmoke.m').read_text()
    for required in ('eager navigation view does not build content before configuration','rapid duplicate click invokes exactly once',
        'weak URL fields survive handler','UIKeyboardDidShowNotification','becomeFirstResponder',
        'software keyboard actually shown','UIContentSizeCategoryAccessibilityExtraExtraExtraLarge',
        'dialog-long-dark.png','new sheet presented after previous dismissed','real controller busy released after cancel/error',
        'real import and diagnostics open expanded without a swipe',
        'full-screen capture completed before keyboard dismissal',
        'short confirmation uses the centered card','short confirmation is not a bottom sheet',
        'cancel precedes confirm in one centered card','paired actions share one row',
        'QHDialogSetterSpy dialogControllerWithTitle:', 'lastStoredPresentationStyle==expected',
        'lastStoredTransitionStyle==transition', 'animated:stage<=1',
        'QHDialogInspectField(', '[window hitTest:', 'answers window hitTest at every valid text point',
        'focus switches to the URL field inside the same dialog', 'source name text survives the handler as its own value',
        'entrance.presentationCompleted=YES', 'completedPresentationSamples>=2',
        'configuredAppearanceSample=^(QHDialogController *appearing)',
        'configured appearance sampled before viewDidAppear',
        'card=(UIView *)[dialog valueForKey:@"centeredCard"];',
        'checkEntranceRecord:entrance card:(UIView *)[dialog valueForKey:@"centeredCard"]',
        'centered card model transform never scales on entrance',
        'centered card presentation layer never springs while dismissing'):
        assert required in smoke,required
    assert 'QHRunDialogSmoke(self.controller,' in (ROOT/'Tests/VisualSmoke.m').read_text()
    driver=(ROOT/'ci/visual_smoke.py').read_text()
    assert 'Tests/DialogSmoke.m' in driver
    assert "'-framework','QuartzCore'" in driver
    print(f'Native10 source: 7 unified dialog entries, input hit-area/modal timing contracts, {len(mutations)} rejected mutations and 3 opaque icon sizes PASS')
    print('UIKit dismissal, input and keyboard runtime acceptance require macOS CI; not tested by this script.')
if __name__=='__main__':main()
