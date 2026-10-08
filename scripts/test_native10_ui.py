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
    assert 'view.keyboardLayoutGuide.topAnchor' in dialog
    assert 'UISheetPresentationControllerDetent.mediumDetent' in dialog
    handler=dialog.split('- (void)chooseAction:',1)[1].split('- (void)viewDidLoad',1)[0]
    for required in ('if (self.resolving', 'self.resolving=YES', 'self.view.userInteractionEnabled=NO',
        'QHDialogController *keepAlive=self', 'completion:^{', 'if (action.handler) action.handler(action)', 'keepAlive.mutableActions=nil'):
        assert required in handler, required
    assert handler.index('dismissViewControllerAnimated') < handler.index('action.handler(action)')
    assert 'UIAlertActionStyleCancel' in dialog and 'UIAlertActionStyleDestructive' in dialog
    assert 'DColor(0xb42336,0xff8995)' in dialog
    assert 'DColor(0xffffff,0x13131a)' in dialog
    assert 'NSAssert(!self.isViewLoaded' in dialog
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
    for old,new in [('self.resolving=YES','self.resolving=NO'),('QHDialogController *keepAlive=self','QHDialogController *keepAlive=nil'),('controller.modalInPresentation=YES','controller.modalInPresentation=NO')]:
        changed=dialog.replace(old,new);assert changed!=dialog
        try:check(changed,controller)
        except AssertionError:pass
        else:raise AssertionError('Unsafe mutation accepted: '+old)
    for name,size in [('Icon1024.png',1024),('Icon60@3x.png',180),('Icon60@2x.png',120)]:check_icon(ROOT/'App/Resources'/name,size)
    assert 'QHDialogController.m' in (ROOT/'App/Makefile').read_text()
    smoke=(ROOT/'Tests/DialogSmoke.m').read_text()
    for required in ('factory configuration precedes view loading','rapid duplicate click invokes exactly once',
        'weak URL fields survive handler','UIKeyboardDidShowNotification','becomeFirstResponder',
        'software keyboard actually shown','UIContentSizeCategoryAccessibilityExtraExtraExtraLarge',
        'dialog-long-dark.png','new sheet presented after previous dismissed','real controller busy released after cancel/error'):
        assert required in smoke,required
    assert 'QHRunDialogSmoke(self.controller,' in (ROOT/'Tests/VisualSmoke.m').read_text()
    assert 'Tests/DialogSmoke.m' in (ROOT/'ci/visual_smoke.py').read_text()
    print('Native10 source: 7 unified dialog entries, preview/editor chrome, 3 rejected safety mutations and 3 opaque icon sizes PASS')
    print('UIKit dismissal, input and keyboard runtime acceptance require macOS CI; not tested by this script.')
if __name__=='__main__':main()
