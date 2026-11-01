"""Native10 dialog/icon contracts updated for the shared native17 presentation.

Actual UIKit lifecycle/input tests run only in CI. The chooseAction byte freeze
is the unchanged pre-native17 dismissal/handler contract, not a new UI golden.
"""
from pathlib import Path
import hashlib
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
CHOOSE_ACTION_SHA256 = '055671b63bc00f2af8117971d6b88d94caa0c7b32500db15dc80a7f2a461203e'


def section(source, start, end):
    result = source[source.index(start):]
    return result[:result.index(end)] if end else result


def check(dialog, controller, components=None):
    if components is None:
        components = (ROOT / 'App/QHVisualComponents.m').read_text(encoding='utf-8')
    assert '[UIAlertController' not in controller and '[UIAlertAction' not in controller
    assert controller.count('dialogControllerWithTitle:') == 7
    assert controller.count('QHConfigureModal(nav);') == 2
    assert 'modalPresentationStyle=UIModalPresentationFormSheet' in dialog
    assert 'controller.modalInPresentation=YES' in dialog
    for required in ('sheet.detents=@[UISheetPresentationControllerDetent.largeDetent]',
                     'customDetentWithIdentifier:@"qh.menu"', 'UISheetPresentationControllerDetent.mediumDetent',
                     'sheet.selectedDetentIdentifier=@"qh.menu"',
                     'sheet.prefersGrabberVisible=YES', 'sheet.preferredCornerRadius=28;',
                     'view.keyboardLayoutGuide.topAnchor',
                     'sheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierLarge;',
                     '- (BOOL)usesCenteredConfirmation', 'UIModalPresentationOverFullScreen',
                     'UIModalTransitionStyleCrossDissolve', '[self buildCenteredConfirmation];',
                     'self.centeredCard=card;', '[self setNavigationBarHidden:YES animated:NO];',
                     'holder.layer.cornerRadius=12;', 'field.borderStyle=UITextBorderStyleNone'):
        assert required in dialog, required
    # Compact confirmation is a stacked decision, not a reused info row.
    confirm = section(dialog, '- (void)buildCenteredConfirmation {', '- (void)chooseAction:')
    assert 'card.accessibilityIdentifier=@"qh.dialog.confirm";' in confirm
    assert 'QHConfirmTextBlock(self.content.title,self.detail)' in confirm
    assert 'QHVInfo(' not in confirm, 'Compact confirmation no longer reuses the icon info row'
    assert 'QHCenteredActionButton(' not in dialog, 'The old side-by-side confirm button must stay removed'
    assert '[card addArrangedSubview:QHConfirmButton(primary,YES,self)];' in confirm
    assert '[card addArrangedSubview:QHConfirmButton(cancel,!primary,self)];' in confirm
    assert confirm.index('[card addArrangedSubview:QHConfirmButton(primary,YES,self)];') < \
        confirm.index('[card addArrangedSubview:QHConfirmButton(cancel,!primary,self)];'), 'Primary action must precede the escape action'
    assert 'constraintGreaterThanOrEqualToConstant:primary ? 46 : 44' in dialog, 'Confirm actions keep touch-friendly heights'
    fields = section(dialog, 'for (UITextField *field in self.mutableFields)', '__weak typeof(self) weak=self;')
    assert 'field.translatesAutoresizingMaskIntoConstraints=NO;' in fields
    assert fields.index('field.translatesAutoresizingMaskIntoConstraints=NO;') < fields.index('[holder addSubview:field];')
    for required in ('[field.topAnchor constraintEqualToAnchor:holder.topAnchor]',
                     '[field.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor]',
                     '[field.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:12]',
                     '[field.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:-12]',
                     '[holder.heightAnchor constraintGreaterThanOrEqualToConstant:44]',
                     'label.numberOfLines=0', 'label.adjustsFontForContentSizeCategory=YES'):
        assert required in fields, required
    assert 'CGAffineTransformMakeScale' not in dialog and 'usingSpringWithDamping' not in dialog
    assert '- (UIModalPresentationStyle)modalPresentationStyle' not in dialog, 'Use the actual UIKit setter, not a dynamic getter'
    assert '- (UIModalTransitionStyle)modalTransitionStyle' not in dialog
    configure = section(dialog, 'void QHConfigureModal(', '@interface QHDialogAction')
    assert 'controller.modalPresentationStyle=centered ? UIModalPresentationOverFullScreen' in configure
    assert 'controller.modalTransitionStyle=centered ? UIModalTransitionStyleCrossDissolve' in configure
    assert 'if (!centered) {' in configure
    assert configure.index('if (!centered) {') < configure.index('controller.sheetPresentationController')
    actions = section(dialog, '- (void)addAction:', '- (void)addTextFieldWithConfigurationHandler:')
    add_fields = section(dialog, '- (void)addTextFieldWithConfigurationHandler:', '- (void)buildCenteredConfirmation')
    assert 'QHConfigureModal(self);' in actions and 'QHConfigureModal(self);' in add_fields
    appearance = section(dialog, '- (void)viewWillAppear:', None)
    assert 'QHConfigureModal(self)' not in appearance, 'Do not switch modal properties during entry'
    for required in ('[canvas addSubview:card];', '[root addSubview:scroll];', '[scroll addSubview:canvas];',
                     'UIButtonConfiguration.plainButtonConfiguration',
                     'NSAssert(!self.contentBuilt', 'if (self.contentBuilt) return;', 'self.contentBuilt=YES;'):
        assert required in dialog, required
    assert '- (void)viewDidLoad' not in dialog
    assert 'readwrite' not in (ROOT / 'App/QHDialogController.h').read_text(encoding='utf-8')
    assert 'QHCenteredConfirmationFor(' in dialog and 'NSCharacterSet.newlineCharacterSet' in dialog
    decision = section(dialog, 'static BOOL QHCenteredConfirmationFor(', 'static UIView *QHConfirmTextBlock(')
    assert 'style==UIAlertControllerStyleAlert && fields==0 && actions>0 && actions<=2' in decision
    assert 'detail.length<500' in decision
    handler = section(dialog, '- (void)chooseAction:(QHDialogAction *)action {', '- (void)viewWillAppear:')
    for required in ('if (self.resolving', 'self.resolving=YES', 'self.view.userInteractionEnabled=NO',
                     'QHDialogController *keepAlive=self', 'completion:^{',
                     'if (action.handler) action.handler(action)', 'keepAlive.mutableActions=nil'):
        assert required in handler, required
    assert handler.index('dismissViewControllerAnimated') < handler.index('action.handler(action)')
    assert hashlib.sha256(handler.encode('utf-8')).hexdigest() == CHOOSE_ACTION_SHA256, 'Frozen chooseAction bytes changed'
    assert 'UIAlertActionStyleCancel' in dialog and 'UIAlertActionStyleDestructive' in dialog
    # Only semantic tokens, including opaque primary/destructive foregrounds.
    assert 'DColor(' not in dialog, 'Do not keep the obsolete dialog palette or dead aliases'
    for required in ('#import "QHVisualComponents.h"', 'controller.view.tintColor=QHVAccentColor()',
                     'appearance.backgroundColor=QHVBackgroundColor()', 'field.textColor=QHVPrimaryTextColor()',
                     'field.backgroundColor=QHVInnerColor()', 'label.textColor=QHVSecondaryTextColor()',
                     'configuration.baseForegroundColor=QHVPrimaryForegroundColor()',
                     'configuration.baseBackgroundColor=action.style==UIAlertActionStyleDestructive ? QHVDestructiveColor() : QHVAccentColor()',
                     'scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]',
                     'NSDirectionalEdgeInsetsMake(12,16,12,16)',
                     '[stack addArrangedSubview:QHConfirmButton(action,YES,self)];'):
        assert required in dialog, required
    # One text block and one filled-action spec serve compact and expanded dialogs.
    assert dialog.count('QHConfirmTextBlock(self.content.title,self.detail)') == 2, 'Both dialog shapes share the same title/body block'
    assert 'QHVInfo(self.content.title' not in dialog, 'Dialogs must not fall back to the icon info row'
    # P2 menu: options share one list directly on the sheet background, not
    # another card. Cancellation is its own group below the list and still
    # routes through chooseAction; non-menu dialogs keep the navigation close.
    choices = section(appearance, '__weak typeof(self) weak=self;', None)
    assert choices.index('UIStackView *choices=nil;') < choices.index('for (QHDialogAction *action in self.mutableActions)')
    assert 'choices=[UIStackView new];' in choices and 'choices=QHVCard();' not in choices
    assert 'if (!choices) {' in choices, 'Menu list is created once, not once per row'
    assert 'choices.axis=UILayoutConstraintAxisVertical;' in choices
    assert 'choices.accessibilityIdentifier=@\"qh.dialog.choices\";' in choices
    assert '[stack addArrangedSubview:choices];' in choices
    assert 'if (choices.arrangedSubviews.count) [choices addArrangedSubview:QHVSeparator()];' in choices
    assert '[choices addArrangedSubview:menuRow];' in choices
    assert 'constraintGreaterThanOrEqualToConstant:52' in choices, 'Menu rows are 52pt'
    assert 'UIStackView *choice=QHVCard();' not in choices
    assert choices.index('UIAlertActionStyleCancel') < choices.index('self.dialogStyle==UIAlertControllerStyleActionSheet')
    assert 'self.content.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithCustomView:close]' in choices
    assert 'QHDialogAction *menuCancel=nil;' in choices
    # P3 form: title lives in the navigation bar, body paragraphs sit on the
    # sheet, inputs are plain page groups with label 8pt above the holder.
    assert 'self.content.navigationItem.title=self.content.title;' in appearance
    assert 'QHFormBodyBlock(self.detail)' in dialog
    assert 'qh.dialog.body' in dialog
    assert 'UIStackView *inputs=[UIStackView new];' in appearance and 'inputs=QHVCard();' not in appearance
    assert 'setCustomSpacing:8 afterView:label' in appearance
    assert 'QHConfirmButton(menuCancel,NO,self)' in choices, 'Menu cancel is a text button in its own group'
    assert 'cancelGroup.accessibilityIdentifier=@\"qh.dialog.cancel\";' in choices
    assert '[close.heightAnchor constraintGreaterThanOrEqualToConstant:44]' in choices
    assert '[close.widthAnchor constraintGreaterThanOrEqualToConstant:44]' in choices
    assert 'constant:22' not in controller, 'Editor insets must match the shared 18pt rhythm'
    button = section(controller, 'static UIButton *Button(', 'static NSString *Number(')
    assert 'UIFontTextStyleSubheadline' not in button
    assert 'UIFontTextStyleBody' in button and 'constraintGreaterThanOrEqualToConstant:46' in button
    assert 'initWithCustomView:Button(QHL(@"Cancel")' in controller
    assert controller.index('sampleCard]') < controller.index('Button(button, YES, YES, ^{')
    row = section(components, 'static UIControl *VActionRow(', 'static UIView *VStat(')
    assert 'accessibilityHint' not in row, 'Row subtitle must not be announced as a hint'


    # P4: only the draft-saved success is a light toast. It must not
    # intercept touches, must be at least 44pt tall, must use no scale or
    # spring, and must remove itself after 3.0s. Failures and Hosts
    # operation results stay in blocking dialogs.
    toast_view = section(components, 'UIView *QHVToastView(NSString *text) {', 'void QHVShowToast')
    toast_show = section(components, 'void QHVShowToast(UIView *host, NSString *text) {', '')
    assert 'pill.accessibilityIdentifier = @"qh.toast";' in toast_view
    assert 'pill.userInteractionEnabled = NO;' in toast_view
    assert 'constraintGreaterThanOrEqualToConstant:44' in toast_view
    assert 'CGAffineTransformMakeScale' not in toast_view and 'usingSpringWithDamping' not in toast_view
    assert '(3.0 * NSEC_PER_SEC)' in toast_show
    assert 'removeFromSuperview' in toast_show
    assert 'QHVShowToast(weak.rootController.view, QHL(@"Saved locally · not applied"));' in controller
    assert 'QHL(@"Nothing saved") detail:error.localizedDescription' in controller
    assert '[self message:title detail:detail];' in controller


def check_icon(path, size):
    raw = path.read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n'
    pos = 8
    has_data = False
    while pos < len(raw):
        length = struct.unpack_from('>I', raw, pos)[0]
        kind = raw[pos + 4:pos + 8]
        data = raw[pos + 8:pos + 8 + length]
        assert zlib.crc32(kind + data) & 0xffffffff == struct.unpack_from('>I', raw, pos + 8 + length)[0]
        if kind == b'IHDR':
            width, height, depth, color, *_ = struct.unpack('>IIBBBBB', data)
            assert (width, height, depth, color) == (size, size, 8, 2), 'Expected opaque 8bit RGB icon'
        if kind == b'tRNS':
            raise AssertionError('Transparent icon')
        if kind == b'IDAT':
            has_data = True
        pos += 12 + length
    assert has_data


def main():
    dialog = (ROOT / 'App/QHDialogController.m').read_text(encoding='utf-8')
    controller = (ROOT / 'App/QHAppController.m').read_text(encoding='utf-8')
    components = (ROOT / 'App/QHVisualComponents.m').read_text(encoding='utf-8')
    check(dialog, controller, components)
    # Every native16 geometry/modal/input/lifetime mutation remains, with new
    # shared-palette/grouping negatives instead of obsolete DColor snapshots.
    mutations = [
        ('self.resolving=YES', 'self.resolving=NO'),
        ('QHDialogController *keepAlive=self', 'QHDialogController *keepAlive=nil'),
        ('controller.modalInPresentation=YES', 'controller.modalInPresentation=NO'),
        ('sheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierLarge;',
         'sheet.selectedDetentIdentifier=UISheetPresentationControllerDetentIdentifierMedium;'),
        ('UIModalPresentationOverFullScreen', 'UIModalPresentationPageSheet'),
        ('[self buildCenteredConfirmation];', ''),
        ('field.translatesAutoresizingMaskIntoConstraints=NO;', ''),
        ('self.centeredCard=card;', 'self.centeredCard=card; card.transform=CGAffineTransformMakeScale(1.08,1.08);'),
        ('QHConfigureModal(self);', ''),
        ('controller.modalPresentationStyle=centered ? UIModalPresentationOverFullScreen',
         'controller.modalPresentationStyle=centered ? UIModalPresentationFormSheet'),
        ('    if (!centered) {\n        UISheetPresentationController *sheet=',
         '    {\n        UISheetPresentationController *sheet='),
        ('    [super viewWillAppear:animated];', '    [super viewWillAppear:animated]; QHConfigureModal(self);'),
        ('[field.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:12]',
         '[field.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:0]'),
        ('QHVPrimaryForegroundColor()', 'QHVAccentColor()'),
        ('if (!choices) {', 'if (YES) {'),
        ('choices=[UIStackView new];', 'choices=QHVCard();'),
        ('QHFormBodyBlock(self.detail)', 'QHConfirmTextBlock(self.content.title,self.detail)'),
        ('self.content.navigationItem.title=self.content.title;', 'self.content.navigationItem.title=@"";'),
        ('QHConfirmButton(menuCancel,NO,self)', 'QHConfirmButton(menuCancel,YES,self)'),
        ('constraintGreaterThanOrEqualToConstant:52', 'constraintGreaterThanOrEqualToConstant:44'),
        ('choices.accessibilityIdentifier=@"qh.dialog.choices";', ''),
        ('scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]',
         'scaledFontForFont:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]'),
        ('[card addArrangedSubview:QHConfirmButton(cancel,!primary,self)];',
         '[card addArrangedSubview:QHConfirmButton(cancel,YES,self)];'),
        ('[card addArrangedSubview:QHConfirmButton(primary,YES,self)];',
         '[card addArrangedSubview:QHConfirmButton(primary,NO,self)];'),
        ('card.accessibilityIdentifier=@"qh.dialog.confirm";', ''),
        ('QHConfirmTextBlock(self.content.title,self.detail)',
         'QHVInfo(self.content.title,self.detail,@"doc.text",nil)'),
        ('constraintGreaterThanOrEqualToConstant:primary ? 46 : 44',
         'constraintGreaterThanOrEqualToConstant:primary ? 40 : 30'),
    ]
    for old, new in mutations:
        changed = dialog.replace(old, new)
        assert changed != dialog, 'Mutation target missing: ' + old
        try:
            check(changed, controller, components)
        except AssertionError:
            pass
        else:
            raise AssertionError('Unsafe mutation accepted: ' + old)
    for name, size in [('Icon1024.png', 1024), ('Icon60@3x.png', 180), ('Icon60@2x.png', 120)]:
        check_icon(ROOT / 'App/Resources' / name, size)
    assert 'QHDialogController.m' in (ROOT / 'App/Makefile').read_text(encoding='utf-8')
    smoke = (ROOT / 'Tests/DialogSmoke.m').read_text(encoding='utf-8')
    for required in ('eager navigation view does not build content before configuration', 'rapid duplicate click invokes exactly once',
                     'weak URL fields survive handler', 'UIKeyboardDidShowNotification', 'becomeFirstResponder',
                     'software keyboard actually shown', 'UIContentSizeCategoryAccessibilityExtraExtraExtraLarge',
                     'dialog-long-dark.png', 'new sheet presented after previous dismissed',
                     'real controller busy released after cancel/error',
                     'real import and diagnostics open expanded without a swipe',
                     'full-screen capture completed before keyboard dismissal',
                     'short confirmation uses the centered card', 'short confirmation is not a bottom sheet',
                     'primary action sits above the text-only cancel', 'stacked dialog actions share one centered column',
                     'stacked dialog actions share the card width', 'stacked dialog actions keep touch-friendly heights',
                     'QHDialogSetterSpy dialogControllerWithTitle:', 'lastStoredPresentationStyle==expected',
                     'lastStoredTransitionStyle==transition', 'animated:stage<=1',
                     'QHDialogInspectField(', '[window hitTest:', 'answers window hitTest at every valid text point',
                     'focus switches to the URL field inside the same dialog',
                     'source name text survives the handler as its own value',
                     'entrance.presentationCompleted=YES', 'completedPresentationSamples>=2',
                     'configuredAppearanceSample=^(QHDialogController *appearing)',
                     'configured appearance sampled before viewDidAppear',
                     'card=(UIView *)[dialog valueForKey:@"centeredCard"];',
                     'checkEntranceRecord:entrance card:(UIView *)[dialog valueForKey:@"centeredCard"]',
                     'centered card model transform never scales on entrance',
                     'centered card presentation layer never springs while dismissing'):
        assert required in smoke, required
    visual = (ROOT / 'Tests/VisualSmoke.m').read_text(encoding='utf-8')
    assert 'QHRunDialogSmoke(self.controller,' in visual
    for required in ('qh.toast', 'toast removes itself after 3 seconds',
                     'a second toast replaces the first instead of stacking',
                     'toast is visible, non-blocking and at least 44pt tall'):
        assert required in visual, required
    driver = (ROOT / 'ci/visual_smoke.py').read_text(encoding='utf-8')
    assert 'Tests/DialogSmoke.m' in driver
    assert "'-framework','QuartzCore'" in driver
    print(f'Native10 source: 7 unified dialog entries, shared palette/one choices group, unchanged chooseAction hash, '
          f'input hit-area/modal timing contracts, {len(mutations)} rejected mutations and 3 opaque icon sizes PASS')
    print('UIKit dismissal, input and keyboard runtime acceptance require macOS CI; not tested by this script.')


if __name__ == '__main__':
    main()
