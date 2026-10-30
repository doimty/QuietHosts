"""Native9 structure/routing/frozen-scope checks, not UIKit visual acceptance.

The presentation may evolve; frozen business routines and file hashes may not.
Do not retain an obsolete UI expression merely to satisfy a source snapshot.
"""
from pathlib import Path
import hashlib
import json
import re
from platform_freeze import project_frozen_text

ROOT = Path(__file__).resolve().parents[1]


def segment(ui, start, end):
    value = ui[ui.index(start):]
    return value[:value.index(end)] if end else value


def check(ui):
    home = segment(ui, '- (void)drawHome {', '- (NSString *)sourceKind:')
    for required in (
        'QHVBrandHeader(', 'QHVStatusCard(', 'QHVStats(',
        'mainSwitch.enabled = !self.busy && (active || inactive)',
        '[sender setOn:active animated:NO]',
        '[weak prepareHelperCommand:requested ? @"enable" : @"disable"]',
        'self.draft.compiled.domains.count', 'self.draft.compiled.statistics[@"duplicates"]',
        'QHL(@"Preview and apply")', '[weak prepareApply]',
        'self.appliedLocalRevision', 'self.appliedHelperRevision',
    ):
        assert required in home, required
    assert '[QHBridge request:' not in home, 'Direct bridge write in rendering'
    assert 'int64_t)self.draft.compiled.hostsData.length' in home
    assert home.index('self.draft.compiled.hostsData.length') > home.index('UIStackView *draftCard'), 'Draft bytes mislabelled as managed state'
    assert home.index('QHVStatusCard(') < home.index('UIStackView *draftCard'), 'Verified state precedes the separate local draft'
    rules = segment(ui, '- (void)renderRules {', '- (NSString *)themeTitle')
    for required in ('UIStackView *list = QHVCard()', '[weak openSource:identifier]',
                     'Number(result.domains.count)', 'source[@"enabled"]', 'unsupported', '[weak chooseImport:YES]'):
        assert required in rules, required
    source = segment(ui, '- (void)renderSourceDetail {', '- (void)renderRules {')
    for required in ('self.draft.document[@"sources"]', 'self.detailSourceID', 'if (!source)',
                     'toggle.enabled = !self.busy', '[sender setOn:!enabled animated:NO]',
                     '[weak toggleSource:identifier enabled:enabled]', '[weak removeSource:identifier]'):
        assert required in source, required
    settings = segment(ui, '- (void)renderSettings {', '- (void)retryReload {')
    assert settings.count('QHVSection(') >= 3 and 'CFBundleVersion' in settings and 'CFBundleShortVersionString' in settings
    assert 'QHVRow(QHL(@"Theme")' in settings and '[weak showThemePicker]' in settings
    picker = segment(ui, '- (void)showThemePicker {', '- (void)showUsageGuide')
    assert 'UIAlertControllerStyleActionSheet' in picker and 'popoverPresentationController.sourceView' in picker
    assert 'setObject:key forKey:@"QHTheme"' in picker and 'applyThemeToWindow:' in picker
    preview = segment(ui, '- (void)showPreview:', '- (void)candidateSources:')
    assert preview.count('QHVFormRow(') == 10, 'The whole merged/source-input preview remains visible'
    for required in ('completion:confirm', '[weak finishBusy]', 'nav.modalInPresentation = YES',
                     'p[@"unsupported"]', 'p[@"duplicates"]', 's[@"duplicates"]', 's[@"excluded"]',
                     'preview.compiled.domains.count', 'MIN((NSUInteger)50', 'pushViewController:samplePage'):
        assert required in preview, required


def check_frozen(ui):
    """Retain every historical native9 hash; adapt only the reviewed UI surface.

    Exposed for native17 negative write/consent tests as well. This does not
    remove handlers, normalize business whitespace, or update golden hashes.
    """
    golden = json.loads((ROOT / 'Tests/Native9Frozen.json').read_text(encoding='utf-8'))
    for name, digest in golden['files'].items():
        original = project_frozen_text((ROOT / name).read_bytes().decode('utf-8'), name).encode('utf-8')
        assert hashlib.sha256(original).hexdigest() == digest, 'Frozen file changed: ' + name
    # Native10's UI-only adapter maps back to the exact native9 UIKit type
    # names before comparing frozen business code. No handler text is removed.
    normalized = ui.replace('QHDialogController *', 'UIAlertController *').replace('[QHDialogController', '[UIAlertController')
    normalized = normalized.replace('dialogControllerWithTitle:', 'alertControllerWithTitle:')
    normalized = normalized.replace('QHDialogAction *', 'UIAlertAction *').replace('[QHDialogAction', '[UIAlertAction')
    normalized = normalized.replace('    QHConfigureModal(nav);\n', '')
    copy = json.loads((ROOT / 'Tests/DependencyCopy.json').read_text(encoding='utf-8'))
    assert normalized.count(copy['new']) == 1, 'Unexpected dependency-copy change'
    normalized = normalized.replace(copy['new'], copy['old'])
    for item in golden['methods']:
        digest = hashlib.sha256(segment(normalized, item['start'], item['end']).encode('utf-8')).hexdigest()
        assert digest == item['sha256'], 'Frozen controller routine changed: ' + item['start']


def must_reject(checker, original, old, new):
    changed = original.replace(old, new)
    assert changed != original, 'Mutation target missing: ' + old
    try:
        checker(changed)
    except AssertionError:
        return
    raise AssertionError('UI/frozen mutation accepted: ' + old)


def main():
    ui = (ROOT / 'App/QHAppController.m').read_text(encoding='utf-8')
    check(ui)
    ui_mutations = [
        ('QHVBrandHeader(', 'OldBrand('),
        ('QHVStats(', 'OldStats('),
        ('QHVStatusCard(', 'OldStatus('),
        ('[sender setOn:active animated:NO]', '[sender setOn:requested animated:NO]'),
        ('completion:confirm', 'completion:nil'),
    ]
    for old, new in ui_mutations:
        must_reject(check, ui, old, new)
    check_frozen(ui)
    frozen_mutations = [
        ('[QHBridge request:@"apply"', '[QHBridge request:@"reload"'),
        ('if (adoption) {', 'if (YES) {'),
        ('weak.appliedLocalRevision = nil;', 'weak.appliedLocalRevision = @"guessed-from-count";'),
    ]
    for old, new in frozen_mutations:
        must_reject(check_frozen, ui, old, new)
    components = (ROOT / 'App/QHVisualComponents.m').read_text(encoding='utf-8')
    for required in ('UIContentSizeCategoryIsAccessibilityCategory', 'scaledValueForValue:self.baseWidth',
                     'UIContentSizeCategoryDidChangeNotification',
                     'self.equalColumns ? UIStackViewAlignmentFill : UIStackViewAlignmentLeading',
                     'constraintGreaterThanOrEqualToConstant:44', 'label.numberOfLines = 0',
                     'control.accessibilityValue = value', 'content.accessibilityElementsHidden = YES'):
        assert required in components, required
    for name in re.findall(r'static [^\n]+? \*?(V\w+)\(', components):
        assert len(re.findall(r'\b' + name + r'\s*\(', components)) > 1, 'Unused helper: ' + name
    build = (ROOT / 'App/Makefile').read_text(encoding='utf-8')
    assert 'QHVisualComponents.m' in build and 'VisualSmoke.m' not in build
    smoke = (ROOT / 'ci/visual_smoke.py').read_text(encoding='utf-8')
    assert 'Shared/QHBridge.m' not in smoke and 'Tests/VisualSmoke.m' in smoke
    assert "report['writes']==0" in smoke
    assert 'ci/visual_smoke.py' in (ROOT / '.github/workflows/native.yml').read_text(encoding='utf-8')
    assert not (ROOT / 'Module').exists()
    print(f'Native9: four-page structure, explicit consent/routing, dynamic layout, {len(ui_mutations)} UI + '
          f'{len(frozen_mutations)} frozen rejected mutations and unchanged historical frozen scope PASS')
    print('Actual UIKit execution is CI simulator only; device acceptance remains separate.')


if __name__ == '__main__':
    main()
