"""Native9 structure/routing/frozen-scope checks, not UIKit visual acceptance."""
from pathlib import Path
import hashlib, json, re
ROOT=Path(__file__).resolve().parents[1]

def check(ui):
    home=ui.split('- (void)render {',1)[1].split('- (NSString *)sourceKind:',1)[0]
    for required in ('QHVBrandHeader(', 'QHVStats(', 'mainSwitch.enabled = !self.busy && (active || inactive)',
        '[sender setOn:active animated:NO]', '[weak prepareHelperCommand:requested ? @"enable" : @"disable"]',
        'self.draft.compiled.domains.count', 'self.draft.compiled.statistics[@"duplicates"]',
        'Button(QHL(@"Apply draft"), YES', '[weak prepareApply]', 'self.appliedLocalRevision', 'self.appliedHelperRevision'):
        assert required in home,required
    assert '[QHBridge request:' not in home, 'Direct bridge write in rendering'
    assert 'int64_t)self.draft.compiled.hostsData.length' in home
    assert home.index('self.draft.compiled.hostsData.length')>home.index('UIStackView *draftCard'), 'Draft bytes mislabelled as managed state'
    rules=ui.split('- (void)renderRules {',1)[1].split('- (NSString *)themeTitle',1)[0]
    for required in ('UIStackView *list = QHVCard()', '[weak openSource:identifier]', 'Number(result.domains.count)', 'source[@"enabled"]', 'unsupported', '[weak chooseImport:YES]'):
        assert required in rules, required
    source=ui.split('- (void)renderSourceDetail {',1)[1].split('- (void)renderRules {',1)[0]
    for required in ('self.draft.document[@"sources"]', 'self.detailSourceID', 'if (!source)', 'toggle.enabled = !self.busy',
        '[sender setOn:!enabled animated:NO]', '[weak toggleSource:identifier enabled:enabled]', '[weak removeSource:identifier]'):
        assert required in source, required
    settings=ui.split('- (void)renderSettings {',1)[1].split('- (void)retryReload {',1)[0]
    assert settings.count('QHVSection(')>=3 and 'CFBundleVersion' in settings and 'CFBundleShortVersionString' in settings
    assert 'QHVRow(QHL(@"Theme")' in settings and '[weak showThemePicker]' in settings
    picker=ui.split('- (void)showThemePicker {',1)[1].split('- (void)renderSettings {',1)[0]
    assert 'UIAlertControllerStyleActionSheet' in picker and 'popoverPresentationController.sourceView' in picker
    assert 'setObject:key forKey:@"QHTheme"' in picker and 'applyThemeToWindow:' in picker
    preview=ui.split('- (void)showPreview:',1)[1].split('- (void)candidateSources:',1)[0]
    assert preview.count('QHVFormRow(')==10
    for required in ('completion:confirm', '[weak finishBusy]', 'nav.modalInPresentation = YES', 'p[@"unsupported"]', 'p[@"duplicates"]', 's[@"duplicates"]', 's[@"excluded"]', 'preview.compiled.domains.count', 'MIN((NSUInteger)50', 'pushViewController:samplePage'):
        assert required in preview, required

def segment(ui,start,end):
    value=ui[ui.index(start):]
    return value[:value.index(end)] if end else value

def main():
    ui=(ROOT/'App/QHAppController.m').read_text();check(ui)
    for old,new in [('QHVBrandHeader(', 'OldBrand('), ('QHVStats(', 'OldStats('),
        ('[sender setOn:active animated:NO]','[sender setOn:requested animated:NO]'),
        ('completion:confirm','completion:nil')]:
        mutated=ui.replace(old,new)
        assert mutated!=ui
        try:check(mutated)
        except AssertionError:pass
        else:raise AssertionError('UI mutation accepted: '+old)
    golden=json.loads((ROOT/'Tests/Native9Frozen.json').read_text())
    for name,digest in golden['files'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest, 'Frozen file changed: '+name
    for item in golden['methods']:
        assert hashlib.sha256(segment(ui,item['start'],item['end']).encode()).hexdigest()==item['sha256'], 'Frozen controller routine changed: '+item['start']
    components=(ROOT/'App/QHVisualComponents.m').read_text()
    for required in ('UIContentSizeCategoryIsAccessibilityCategory', 'scaledValueForValue:self.baseWidth', 'UIContentSizeCategoryDidChangeNotification',
        'self.equalColumns ? UIStackViewAlignmentFill : UIStackViewAlignmentLeading', 'constraintGreaterThanOrEqualToConstant:44',
        'label.numberOfLines = 0', 'control.accessibilityValue = value', 'content.accessibilityElementsHidden = YES'):
        assert required in components,required
    for name in re.findall(r'static [^\n]+? \*?(V\w+)\(',components):
        assert len(re.findall(r'\b'+name+r'\s*\(',components))>1, 'Unused helper: '+name
    build=(ROOT/'App/Makefile').read_text()
    assert 'QHVisualComponents.m' in build and 'VisualSmoke.m' not in build
    smoke=(ROOT/'ci/visual_smoke.py').read_text()
    assert 'Shared/QHBridge.m' not in smoke and 'Tests/VisualSmoke.m' in smoke
    assert "report['writes']==0" in smoke
    assert 'ci/visual_smoke.py' in (ROOT/'.github/workflows/native.yml').read_text()
    assert not (ROOT/'Module').exists()
    print('Native9: four-page structure, explicit consent/routing, dynamic layout, 4 rejected mutations and frozen scope PASS')
    print('Actual UIKit execution is CI simulator only; device acceptance remains separate.')
if __name__=='__main__':main()
