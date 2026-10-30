"""Native17 product UI source contracts and deliberately rejected regressions.

These are source/model gates, not executed UIKit screenshots or device proof.
VisualSmoke supplies independent real-controller, Dynamic Type, native-switch,
count/consent/cancellation checks on disposable macOS CI only.
"""
from pathlib import Path
import re
from localization_core import extract_literals, parse_strings, placeholders
from test_native9_ui import check_frozen
from test_ui_palette import check as check_palette

ROOT = Path(__file__).resolve().parents[1]
LEXICAL = re.compile(r'/\*.*?\*/|//[^\n]*|@?"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', re.S)
COMMANDS = {
    'Read local storage again', 'Hide this tip', 'Cancel download', 'Update online sources',
    'Refresh file status', 'Remove from local draft', 'Retry DNS reload',
    'Pause rules and restore original Hosts', 'Resume saved rules',
}
NAVIGATION = {
    'Your rule draft', 'Add source', 'Exact allowlist', 'Theme', 'Backup and restore',
    'Advanced information', 'Using QuietHosts', 'Privacy and local data',
    'Project and support', 'Dependencies', 'Sample · first 50 merged domains at most',
}
NEW_KEYS = {
    'On device', 'Local Hosts manager', 'Verified file state', 'Managed domains', 'Saved domains',
    'Your rule draft', 'Draft domains', 'Duplicates removed', 'Add your first source',
    'Preview and apply', 'Preview before applying. Saved Hosts stay unchanged until you confirm.',
    'Start in three steps',
    'Import a source you trust, review the merged rules, then explicitly apply. Nothing is applied during installation.',
    'Quick actions', 'All online sources, including excluded ones. Updates change the draft only.',
    'Your rule library', '%@ sources · %@ draft domains',
    'Edit locally. Preview and apply when you are ready.', 'Rule control', 'Help and privacy',
    'Using QuietHosts', 'Privacy and local data', 'Project and support',
    'Import, review, apply. Restore when needed.', 'Understand what stays on this device.',
    'Opens GitHub. No report is sent automatically.',
    'Could not open the project page. Please try again later.',
}


def mask(source):
    """Preserve offsets/braces in code, not in strings or comments."""
    return LEXICAL.sub(lambda match: ''.join('\n' if char == '\n' else ' ' for char in match.group()), source)


def compact(source):
    # Contract expressions contain no comments. Whitespace is not a UI golden.
    return re.sub(r'\s+', '', source)


def balanced_end(source, start):
    code = mask(source)
    pairs = {'(': ')', '[': ']', '{': '}'}
    assert code[start] in pairs, 'Expected opening delimiter'
    stack = []
    for index in range(start, len(code)):
        char = code[index]
        if char in pairs:
            stack.append(pairs[char])
        elif char in pairs.values():
            assert stack and char == stack.pop(), 'Unbalanced UI source delimiters'
            if not stack:
                return index + 1
    raise AssertionError('Unclosed UI source delimiters')


def method(source, name):
    match = re.search(r'(?m)^- \([^)]+\)\s*' + re.escape(name) + r'(?=\s*[:{])', mask(source))
    assert match, 'Missing controller method: ' + name
    start = mask(source).index('{', match.end())
    return source[start + 1:balanced_end(source, start) - 1]


def function(source, name):
    code = mask(source)
    for match in re.finditer(r'\b' + re.escape(name) + r'\s*\(', code):
        start = code.index('(', match.start())
        end = balanced_end(source, start)
        rest = re.match(r'\s*\{', code[end:])
        if rest:
            brace = end + rest.end() - 1
            return source[brace + 1:balanced_end(source, brace) - 1]
    raise AssertionError('Missing shared component function: ' + name)


def calls(source, names):
    code = mask(source)
    result = []
    pattern = r'\b(' + '|'.join(map(re.escape, names)) + r')\s*\('
    for match in re.finditer(pattern, code):
        start = code.index('(', match.start())
        end = balanced_end(source, start)
        args, last, depth = [], start + 1, 0
        for index in range(start + 1, end - 1):
            char = code[index]
            if char in '([{':
                depth += 1
            elif char in ')]}':
                depth -= 1
            elif char == ',' and depth == 0:
                args.append(source[last:index].strip())
                last = index + 1
        args.append(source[last:end - 1].strip())
        result.append((match.group(1), args, match.start(), end))
    return result


def without_user_actions(source):
    """Erase only explicit row/button/UIAction handlers, not arbitrary async work.

    A render-time download hidden in dispatch_async must still be detected.
    """
    spans = []
    for _, args, start, end in calls(source, ('QHVRow', 'QHVCommandRow', 'Button')):
        assert args, 'UI action needs arguments'
        if args[-1].lstrip().startswith('^'):
            code = mask(source)
            brace = code.index('{', source.rfind(args[-1], start, end))
            spans.append((brace, balanced_end(source, brace)))
    code = mask(source)
    for match in re.finditer(r'\bactionWithHandler\s*:\s*\^', code):
        brace = code.index('{', match.end())
        spans.append((brace, balanced_end(source, brace)))
    for start, end in sorted(spans, reverse=True):
        source = source[:start] + ' ' * (end - start) + source[end:]
    return source


def check_ui(ui, components, header, dialog):
    home = method(ui, 'drawHome')
    hero = function(components, 'QHVStatusCard')
    masthead = function(components, 'QHVBrandHeader')
    assert home.count('QHVStatusCard(') == 1, 'One managed-state hero, not duplicate protection panels'
    assert 'VFlow(' in masthead and 'QHVCard(' not in masthead and 'QHVIconTile(' not in masthead, 'Brand header is a light masthead'
    # The masthead chip must sit on a card-colored fill and stay intrinsic:
    # the inset fill was invisible in light mode, and the trailing placement
    # stretched it into a full-width bar.
    chip = function(components, 'VMastheadChip')
    assert 'QHVCardColor()' in chip, 'Masthead chip needs a visible surface'
    assert '[tagline addArrangedSubview:chip]' in masthead, 'Chip belongs beside the subtitle'
    assert 'QHVFlexibleStack *tagline = VFlow(220);' in masthead
    assert '[chip setContentHuggingPriority:999 forAxis:UILayoutConstraintAxisHorizontal];' in masthead
    for required in ('QHVStatusCard(', 'QHVCommandRow(', 'QHVRow('):
        assert required in header, required
    for required in ('card.surfaceStyle = QHVSurfaceStyleHero', 'card.accessibilityIdentifier = @"qh.managed.card"',
                     'count.accessibilityIdentifier = @"qh.managed.count"', 'if (countValue != nil)',
                     'QHVFormRow(countTitle, countValue)', '[header addArrangedSubview:toggle]', 'VNativeSwitchSize(toggle)'):
        assert required in hero, required
    assert not re.search(r'toggle\.(?:on|enabled|accessibilityLabel|accessibilityValue)\s*=', mask(hero)), 'Display-only hero does not own state or consent'
    assert '[UISwitch new]' not in hero and 'countValue ?' not in hero and 'countValue ?:' not in hero
    native = function(components, 'VNativeSwitchSize')
    for axis in ('Horizontal', 'Vertical'):
        for priority in ('setContentHuggingPriority', 'setContentCompressionResistancePriority'):
            assert f'{priority}:UILayoutPriorityRequired forAxis:UILayoutConstraintAxis{axis}' in native
    assert 'CGAffineTransformMakeScale' not in components, 'Do not resize a native switch by scaling it'
    for required in ('mainSwitch.on = active', 'mainSwitch.enabled = !self.busy && (active || inactive)',
                     '[sender setOn:active animated:NO]', '[weak prepareHelperCommand:requested ? @"enable" : @"disable"]',
                     'mainSwitch.accessibilityIdentifier = @"qh.managed.switch"', 'NSString *managedCount = nil',
                     '[self.status[@"domainCount"] isKindOfClass:NSNumber.class]',
                     'managedCount = Number([self.status[@"domainCount"] unsignedIntegerValue])'):
        assert required in home, required
    count_condition = re.search(r'if\s*\(([^\n]+domainCount[^\n]+)\)\s*\{', home)
    assert count_condition and 'writable' in count_condition.group(1) and '(active || inactive)' in count_condition.group(1)
    pre_draft = home[:home.index('UIStackView *draftCard')]
    assert 'self.draft.compiled.domains.count' not in pre_draft, 'Managed count must never be the draft count'
    same = re.search(r'\bBOOL\s+same\s*=([^;]+);', home)
    assert same and compact(same.group(1)) == compact(
        '[self.appliedLocalRevision isEqual:self.draft.document[@"revision"]] && '
        '[self.appliedHelperRevision isEqual:self.status[@"revision"]] && active'), 'Applied status requires both revisions, never matching counts'
    first = re.search(r'\bBOOL\s+firstSource\s*=([^;]+);', home)
    assert first and compact(first.group(1)) == compact('[self.draft.document[@"sources"] count] == 0 && !active && !inactive')
    buttons = [args for name, args, _, _ in calls(home, ('Button',)) if name == 'Button' and 'firstSource' in args[0]]
    assert len(buttons) == 1 and len(buttons[0]) == 4
    assert compact(buttons[0][0]) == compact('firstSource ? QHL(@"Add your first source") : QHL(@"Preview and apply")')
    assert compact(buttons[0][2]) == '!self.busy', 'Managed active/paused empty drafts may still explicitly apply'
    assert compact('if (firstSource) [weak chooseImport:NO]; else [weak prepareApply];') in compact(buttons[0][3])
    for required in ('draftCard.accessibilityIdentifier = @"qh.draft.card"', 'apply.accessibilityIdentifier = @"qh.draft.apply"',
                     '[draftCard addArrangedSubview:apply]', '[home addArrangedSubview:draftCard]'):
        assert required in home, required
    assert '[home addArrangedSubview:apply]' not in home and '[managed addArrangedSubview:apply]' not in home
    assert home.index('[draftCard addArrangedSubview:apply]') < home.index('[home addArrangedSubview:draftCard]')
    assert 'if (!self.draftTipDismissed && [self.draft.document[@"sources"] count] == 0)' in home
    assert 'boolForKey:@"QHGuideDismissed"' in method(ui, 'init') and 'setBool:YES forKey:@"QHGuideDismissed"' in home
    # Rendering is scoped: only the visible page is torn down and rebuilt, the
    # rest stay dirty until they are shown. Rebuilding all three per change was
    # the main source of interaction stutter.
    render_body = method(ui, 'render')
    visible_pages = method(ui, 'renderVisiblePages')
    assert 'for (QHPage *page in self.pages) page.needsRender = YES;' in render_body
    assert '[page clear]' not in render_body, 'render() must not tear down pages eagerly'
    assert 'if (!page.viewLoaded || page.view.window == nil) continue;' in visible_pages, 'Off-screen pages stay dirty'
    assert visible_pages.count('[page clear]') == 1
    assert 'if (page.draw) page.draw();' in visible_pages
    assert 'page.draw = ^{' in method(ui, 'init'), 'Each page knows how to draw itself when it appears'
    appearing = method(ui, 'viewWillAppear')
    assert 'if (self.needsRender && self.draw) {' in appearing, 'An appearing page rebuilds itself before the first frame'
    # Slice the implementation, not the forward declaration in the extension.
    dispatch_start = ui.index('- (void)drawPageIndex:(NSUInteger)index {')
    dispatch = ui[dispatch_start:ui.index('\n}\n', dispatch_start)]
    assert '[self drawHome]' in dispatch and '[self renderRules]' in dispatch and '[self renderSettings]' in dispatch
    # Tab appearance must not tear every page down: the passive refresh is
    # silent, skips a fresh helper round trip, and rebuilds only on real change.
    passive = method(ui, 'refreshStatusPassively')
    assert '[weak refreshStatusPassively]' in method(ui, 'init'), 'Page appearance uses the silent refresh'
    assert 'timeIntervalSinceNow] < 5.0' in passive, 'Fresh verified state avoids a redundant helper round trip'
    assert '[self render];' not in passive, 'Passive refresh never rebuilds before the result arrives'
    assert 'self.refreshing = YES;' in passive and 'weak.refreshing = NO;' in passive
    assert 'if (changed && !weak.busy) [weak render];' in passive, 'Rebuild only when the verified state actually changed'
    assert 'previous == nil || ![previous isEqualToDictionary:result]' in passive
    online = method(ui, 'hasOnlineSources')
    assert 'self.draft.document[@"sources"]' in online and '[source[@"kind"] isEqual:@"url"]' in online
    assert compact('if ([source[@"kind"] isEqual:@"url"]) return YES;') in compact(online)
    assert 'return NO' in online and '@"enabled"' not in online and 'boolValue' not in mask(online), 'Any URL snapshot, including excluded ones, enables refresh UI'
    assert 'else if ([self hasOnlineSources])' in home
    assert all('@"enabled"' not in method(ui, name) and 'boolValue' not in mask(method(ui, name)) for name in ('refreshSources', 'refreshBatch'))
    settings = method(ui, 'renderSettings')
    assert '!self.busy && [self hasOnlineSources]' in settings
    assert 'QHL(@"All online sources, including excluded ones. Updates change the draft only.")' in home and 'QHL(@"All online sources, including excluded ones. Updates change the draft only.")' in settings
    for key, handler in (('Using QuietHosts', 'showUsageGuide'), ('Privacy and local data', 'showPrivacyDetails'), ('Project and support', 'openProjectSupport')):
        matching = [args for name, args, _, _ in calls(settings, ('QHVRow',)) if f'QHL(@"{key}")' in args[0]]
        assert len(matching) == 1 and f'[weak {handler}]' in matching[0][-1]
    assert 'openURL:url options:@{}' in method(ui, 'openProjectSupport')
    assert len(re.findall(r'\bopenProjectSupport\b', mask(ui))) == 2, 'Project browser opening is a manual row action only'
    all_rows = []
    for name in ('drawHome', 'renderRules', 'renderSourceDetail', 'renderSettings', 'showPreview'):
        all_rows.extend(calls(method(ui, name), ('QHVRow', 'QHVCommandRow')))
    seen_commands, seen_navigation = set(), set()
    for name, args, _, _ in all_rows:
        assert len(args) == 7
        labels = {key for key, _ in extract_literals(args[0].replace('QHL(', 'NSL('))}
        for label in labels & COMMANDS:
            assert name == 'QHVCommandRow', 'Immediate command must not imply navigation: ' + label
            seen_commands.add(label)
        for label in labels & NAVIGATION:
            assert name == 'QHVRow', 'Navigation needs disclosure: ' + label
            seen_navigation.add(label)
        if 'openSource:' in args[-1]:
            assert name == 'QHVRow', 'Source detail is navigation'
    assert seen_commands == COMMANDS and seen_navigation == NAVIGATION
    assert 'action, YES' in function(components, 'QHVRow') and 'action, NO' in function(components, 'QHVCommandRow')
    builder = function(components, 'VActionRow')
    for required in ('if (action && disclosure)', 'control.isAccessibilityElement = YES',
                     'control.accessibilityValue = value', 'content.accessibilityElementsHidden = YES',
                     'constraintGreaterThanOrEqualToConstant:44', 'control.accessibilityTraits = action ? UIAccessibilityTraitButton'):
        assert required in builder, required
    assert 'constraintEqualToConstant:44' not in builder and 'accessibilityHint' not in builder
    assert 'UIFontTextStyleBody, 16, UIFontWeightSemibold' in function(components, 'VInfo')
    assert 'label.numberOfLines = 0' in function(components, 'VLabel') and 'label.adjustsFontForContentSizeCategory = YES' in function(components, 'VLabel')
    assert 'scaledFontForFont:' in function(components, 'VTypeLabel')
    restore = method(ui, 'restoreScrollPosition')
    clear = method(ui, 'clear')
    consume = method(ui, 'finishScrollRestore')
    assert 'layoutIfNeeded' not in mask(restore + consume), 'Never force off-screen or reentrant layout for scroll recovery'
    assert '[self.scrollView setNeedsLayout]' in restore and 'self.shouldRestoreOffset = YES' in restore
    assert 'if (!self.shouldRestoreOffset) self.rememberedOffset = self.scrollView.contentOffset;' in clear
    assert 'self.shouldRestoreOffset = YES' in clear
    assert 'if (self.contentDidLayout) self.contentDidLayout();' in method(ui, 'layoutSubviews')
    assert 'scroll.contentDidLayout = ^{ [weak finishScrollRestore]; };' in method(ui, 'loadView')
    assert 'preferredWidth.priority = 999;' in method(ui, 'loadView'), 'Viewport column must not be controlled by badge/content hugging'
    for required in ('!self.shouldRestoreOffset', '!self.view.window', 'CGRectGetWidth(scroll.bounds) <= 36',
                     'CGRectGetHeight(scroll.bounds) <= 0', 'scroll.contentSize.height <= 0',
                     'self.shouldRestoreOffset = NO', 'CGPointEqualToPoint(scroll.contentOffset, offset)'):
        assert required in consume, required
    assert consume.index('self.shouldRestoreOffset = NO') < consume.index('setContentOffset:offset'), 'Consume once before offset may trigger another layout'
    preview = method(ui, 'showPreview')
    assert preview.count('QHVFormRow(') == 10 and 'completion:confirm' in preview and '[weak finishBusy]' in preview
    for name in ('drawHome', 'renderRules', 'renderSettings', 'renderSourceDetail'):
        automatic = mask(without_user_actions(method(ui, name)))
        assert not re.search(r'\b(?:QHBridge|downloadURL|startURLString|refreshSources|prepareApply|prepareHelperCommand|openURL|commitPreview|commitCandidate)\b', automatic), 'Implicit operation during rendering: ' + name
    for name in ('init', 'start', 'refreshStatus', 'applyThemeToWindow'):
        body = method(ui, name)
        assert not re.search(r'\b(?:downloadURL|startURLString|refreshSources|prepareApply|prepareHelperCommand|openURL)\b', mask(body)), 'Implicit network/write on startup/status/theme: ' + name
        assert set(re.findall(r'\brequest\s*:\s*@"([^"]+)"', body)) <= {'status'}
    app_code = mask(ui + components + dialog)
    assert not re.search(r'\b(?:NSTimer|CADisplayLink|BGTaskScheduler|BGAppRefreshTask|scheduledTimerWithTimeInterval)\b', app_code)
    assert not re.search(r'\b(?:writeToFile|writeToURL|fopen|freopen|unlink|system|posix_spawn)\b', app_code), 'UI never writes Hosts or launches a helper itself'
    check_palette(ui, components, dialog)


def check_locales(ui, locales, names):
    assert set(locales) == {'en', 'zh-Hans'} and locales['en'].keys() == locales['zh-Hans'].keys()
    used = {key for key, _ in extract_literals(re.sub(r'\bQHL\s*\(', 'NSL(', ui))}
    assert NEW_KEYS <= used, ('Expected product/help copy is no longer wired to QHL', sorted(NEW_KEYS - used))
    for locale, values in locales.items():
        assert used <= values.keys(), ('Missing UI keys', locale, sorted(used - values.keys()))
        for key in used:
            assert values[key] and placeholders(key) == placeholders(values[key]), ('Missing text/format arguments', locale, key)
        for key in NEW_KEYS:
            if locale == 'en':
                # Product-facing English values may be shortened independently
                # of stable QHL keys, just like the Chinese values. They are not
                # an obsolete copy snapshot; existence/format remain mandatory.
                assert re.search(r'[A-Za-z]', values[key]), 'English fallback text missing: ' + key
            else:
                assert re.search(r'[\u3400-\u9fff]', values[key]), 'New product copy needs Chinese-first localization: ' + key
    assert names['en'].get('CFBundleDisplayName') == 'QuietHosts'
    assert names['zh-Hans'].get('CFBundleDisplayName') == '静域'


def check_smoke(smoke):
    for required in ('QHAppController *controller', 'self.window.rootViewController=self.controller.rootController',
                     'QHRunDialogSmoke(self.controller,', 'Check(Writes==0', 'Check(Downloads==0',
                     'ComponentFixtures==18', '@[@320,@375,@428]',
                     'UIContentSizeCategoryExtraExtraExtraLarge', 'UIContentSizeCategoryAccessibilityExtraExtraExtraLarge',
                     'label horizontal containment', '44pt row target', '44pt command target',
                     'number.font.pointSize>normalFont', 'fabs(number.font.pointSize-normalFont)<.1',
                     'class_replaceMethod(QHDownload.class,@selector(startURLString:completion:)',
                     'if (![command isEqual:@"status"]) Writes++'):
        assert required in smoke, required
    matrix = method(smoke, 'runControllerMatrix')
    for required in ('@[@321,@375,@428]', '@[@42,NSNull.null,@"42"]', 'ControllerCases++', 'ControllerCases==108',
                     'self.window.frame=CGRectMake', 'self.controller.rootController.traitOverrides.preferredContentSizeCategory=next',
                     'ControllerLiveTransitions++', 'ControllerLiveTransitions==18',
                     'existing real controller statistic font actually scales', 'real controller normal statistic font restored',
                     'ManagedCountMatches(hero,expected)', 'CheckNativeSwitch(toggle,hero)'):
        assert required in matrix, required
    native = function(smoke, 'NativeSwitchSizeMatches')
    for required in ('[toggle sizeThatFits:CGSizeZero]', 'CGRectGetWidth(toggle.bounds)', 'CGRectGetHeight(toggle.bounds)',
                     'CGRectGetWidth(toggle.frame)', 'CGRectGetHeight(toggle.frame)', 'CGAffineTransformIdentity'):
        assert required in native, required
    for required in ('Check(!NativeSwitchSizeMatches(stretched)', 'native.width+24',
                     'Check(!ManagedCountMatches(syntheticZero,nil)', 'Check(ManagedCountMatches(syntheticZero,@"0")',
                     'equal domain counts never prove applied: both recorded revisions must match',
                     'real Home refresh includes all URLs, including excluded snapshots',
                     '[toggle sendActionsForControlEvents:UIControlEventValueChanged]',
                     '[apply sendActionsForControlEvents:UIControlEventTouchUpInside]',
                     '[cancel sendActionsForControlEvents:UIControlEventTouchUpInside]', 'ConsentCancellations==5',
                     'cancel dismisses the real consent flow and releases busy',
                     'active or paused saved rules can explicitly preview applying an empty draft',
                     '@"page-%lu.png"', '@"page-%lu-dark.png"', '@"source-detail.png"', '@"source-detail-dark.png"',
                     '@"preview.png"', '@"preview-dark.png"', '@"component_fixtures"', '@"controller_cases"',
                     '@"native_switch_checks"', '@"downloads"', '@"controller_live_transitions"', '@"consent_cancellations"'):
        assert required in smoke, required
    assert 'postNotificationName:UIContentSizeCategoryDidChangeNotification' not in smoke
    # A live matrix must retain its view instances between the three categories.
    for body in (method(smoke, 'runFixtures'), matrix):
        code = mask(body)
        for match in re.finditer(r'for \(NSString \*next in', code):
            brace = code.index('{', match.end())
            live = body[brace + 1:balanced_end(body, brace) - 1]
            assert '[self.controller render]' not in live and 'QHVStats(' not in live and 'updateFlow' not in live


def check(ui, components, header, dialog, smoke, locales, names):
    check_ui(ui, components, header, dialog)
    check_locales(ui, locales, names)
    check_smoke(smoke)


def main():
    sources = {
        'ui': (ROOT / 'App/QHAppController.m').read_text(encoding='utf-8'),
        'components': (ROOT / 'App/QHVisualComponents.m').read_text(encoding='utf-8'),
        'header': (ROOT / 'App/QHVisualComponents.h').read_text(encoding='utf-8'),
        'dialog': (ROOT / 'App/QHDialogController.m').read_text(encoding='utf-8'),
        'smoke': (ROOT / 'Tests/VisualSmoke.m').read_text(encoding='utf-8'),
        'locales': {locale: parse_strings((ROOT / f'App/Resources/{locale}.lproj/Localizable.strings').read_text(encoding='utf-8')) for locale in ('en', 'zh-Hans')},
        'names': {locale: parse_strings((ROOT / f'App/Resources/{locale}.lproj/InfoPlist.strings').read_text(encoding='utf-8')) for locale in ('en', 'zh-Hans')},
    }
    check(**sources)
    check_frozen(sources['ui'])
    mutations = [
        ('ui', 'QHVStatusCard(', 'OldStatusCard('),
        ('components', 'return VBadge(text, QHVSecondaryTextColor(), QHVCardColor());',
         'return VBadge(text, QHVSecondaryTextColor(), QHVInnerColor());'),
        ('ui', 'if (!page.viewLoaded || page.view.window == nil) continue;', ''),
        ('ui', 'for (QHPage *page in self.pages) page.needsRender = YES;',
         'for (QHPage *page in self.pages) page.needsRender = NO;'),
        ('ui', 'page.draw = ^{', 'page.appeared = ^{'),
        ('ui', '[self.scrollView setNeedsLayout];', '[self.scrollView layoutIfNeeded];'),
        ('ui', 'preferredWidth.priority = 999;', 'preferredWidth.priority = UILayoutPriorityDefaultHigh;'),
        ('ui', 'if (!self.shouldRestoreOffset) self.rememberedOffset = self.scrollView.contentOffset;', 'self.rememberedOffset = self.scrollView.contentOffset;'),
        ('ui', 'if (self.contentDidLayout) self.contentDidLayout();', '[self layoutSubviews];'),
        ('ui', 'self.shouldRestoreOffset = NO;', 'self.shouldRestoreOffset = YES;'),
        ('ui', '[draftCard addArrangedSubview:apply]', '[home addArrangedSubview:apply]'),
        ('ui', '[sender setOn:active animated:NO]', '[sender setOn:requested animated:NO]'),
        ('ui', '[self.appliedHelperRevision isEqual:self.status[@"revision"]] && active',
         'self.draft.compiled.domains.count == [self.status[@"domainCount"] unsignedIntegerValue] && active'),
        ('ui', '[self.draft.document[@"sources"] count] == 0 && !active && !inactive',
         '[self.draft.document[@"sources"] count] == 0 && !inactive'),
        ('ui', 'YES, !self.busy, ^{',
         'YES, !self.busy && self.draft.compiled.domains.count > 0, ^{'),
        ('ui', 'if (firstSource) [weak chooseImport:NO];',
         'if (firstSource) [weak prepareApply];'),
        ('ui', 'if ([source[@"kind"] isEqual:@"url"]) return YES;',
         'if ([source[@"kind"] isEqual:@"url"] && [source[@"enabled"] boolValue]) return YES;'),
        ('ui', 'QHVCommandRow(QHL(@"Update online sources")', 'QHVRow(QHL(@"Update online sources")'),
        ('ui', 'if (!self.draftTipDismissed && [self.draft.document[@"sources"] count] == 0)', 'if (!self.draftTipDismissed)'),
        ('ui', 'setBool:YES forKey:@"QHGuideDismissed"', 'setBool:YES forKey:@"UnusedGuideKey"'),
        ('ui', 'UIStackView *home = self.pages[0].stack;',
         'UIStackView *home = self.pages[0].stack; [QHBridge request:@"apply" payload:@{} completion:nil];'),
        ('ui', '- (void)start {', '- (void)start { [self downloadURL:@"https://example.invalid/fixture" completion:nil];'),
        ('components', 'if (countValue != nil)', 'if (YES)'),
        ('components', 'return VActionRow(title, subtitle, symbol, value, danger, enabled, action, NO);',
         'return VActionRow(title, subtitle, symbol, value, danger, enabled, action, YES);'),
        ('components', 'if (action && disclosure)', 'if (action)'),
        ('components', '[control.heightAnchor constraintGreaterThanOrEqualToConstant:44]',
         '[control.heightAnchor constraintGreaterThanOrEqualToConstant:32]'),
        ('components', 'UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical',
         'UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisVertical'),
        ('smoke', 'Check(!NativeSwitchSizeMatches(stretched)', 'Check(YES'),
        ('smoke', 'Check(!ManagedCountMatches(syntheticZero,nil)', 'Check(YES'),
        ('smoke', 'QHRunDialogSmoke(self.controller,', 'RemovedDialogSmoke(self.controller,'),
        ('smoke', 'Check(Writes==0', 'Check(YES'),
        ('smoke', 'Check(Downloads==0', 'Check(YES'),
    ]
    for source, old, new in mutations:
        changed = dict(sources)
        changed[source] = sources[source].replace(old, new)
        assert changed[source] != sources[source], 'Mutation target missing: ' + old
        try:
            check(**changed)
        except AssertionError:
            pass
        else:
            raise AssertionError('Native17 unsafe mutation accepted: ' + old)
    locale_mutations = 0
    for kind in ('missing', 'format', 'english-copy', 'display-name'):
        changed = dict(sources)
        changed['locales'] = {name: dict(values) for name, values in sources['locales'].items()}
        changed['names'] = {name: dict(values) for name, values in sources['names'].items()}
        if kind == 'missing':
            del changed['locales']['zh-Hans']['Privacy and local data']
        elif kind == 'format':
            changed['locales']['zh-Hans']['%@ sources · %@ draft domains'] = '%@ 个来源'
        elif kind == 'english-copy':
            changed['locales']['zh-Hans']['Using QuietHosts'] = 'Using QuietHosts'
        else:
            changed['names']['zh-Hans']['CFBundleDisplayName'] = 'QuietHosts'
        try:
            check_locales(changed['ui'], changed['locales'], changed['names'])
        except AssertionError:
            locale_mutations += 1
        else:
            raise AssertionError('Native17 locale/name mutation accepted: ' + kind)
    frozen_mutations = 0
    for old, new in (('NSString *expectedRevision = [status[@"revision"] copy];', 'NSString *expectedRevision = @"guessed-revision";'),
                     ('payload[@"adoptExistingHosts"] = @YES;', 'payload[@"adoptExistingHosts"] = @NO;')):
        changed = sources['ui'].replace(old, new)
        assert changed != sources['ui'], 'Frozen mutation target missing: ' + old
        try:
            check_frozen(changed)
        except AssertionError:
            frozen_mutations += 1
        else:
            raise AssertionError('Frozen business/consent mutation accepted: ' + old)
    print(f'Native17 SOURCE PASS: one native-size managed hero, draft-grouped CTA/revision proof, all-URL manual refresh, '
          f'44pt commands/navigation, bilingual help/privacy/app names and no implicit network/Hosts writes; '
          f'{len(mutations) + locale_mutations + frozen_mutations} rejected mutations; historical frozen hashes unchanged.')
    print('VisualSmoke source retains 18 fixtures + real live DT321/375/428, count/stretch counterexamples, '
          '5 explicit cancellation flows, light/dark controller screenshots and DialogSmoke/write0. '
          'UIKit execution is CI-only and has NOT been run by this Python gate.')


if __name__ == '__main__':
    main()
