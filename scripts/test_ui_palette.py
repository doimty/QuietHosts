"""Source-derived opaque semantic palette checks, not UIKit/AX runtime acceptance.

Parse the QHV*Color -> VColor definitions actually used by the app and shared
components. Legacy controller/dialog Color aliases are not a second palette.
Transparent shadows/borders are deliberately outside opaque text contrast.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TOKEN = re.compile(
    r'(?:static\s+)?UIColor\s*\*\s*(QHV\w+Color|V\w+)\(void\)\s*\{\s*'
    r'return\s+VColor\(0x([0-9a-fA-F]{6}),\s*0x([0-9a-fA-F]{6})\);\s*\}'
)
PUBLIC = {
    'QHVBackgroundColor', 'QHVCardColor', 'QHVInnerColor', 'QHVAccentColor',
    'QHVPrimaryTextColor', 'QHVSecondaryTextColor', 'QHVLineColor',
    'QHVDestructiveColor', 'QHVPrimaryForegroundColor',
}
SURFACES = ('QHVBackgroundColor', 'QHVCardColor', 'QHVInnerColor', 'VHero')
PAIRS = tuple((foreground, background)
              for foreground in ('QHVPrimaryTextColor', 'QHVSecondaryTextColor', 'QHVAccentColor')
              for background in SURFACES) + (
    ('QHVAccentColor', 'VTile'),
    ('VGood', 'VGoodBackground'),
    ('VAttention', 'VAttentionBackground'),
    ('QHVDestructiveColor', 'VDangerBackground'),
    ('QHVDestructiveColor', 'QHVCardColor'),
    ('QHVPrimaryForegroundColor', 'QHVAccentColor'),
    ('QHVPrimaryForegroundColor', 'QHVDestructiveColor'),
)


def code_only(source):
    """Do not mistake comments or quoted example code for token usage."""
    return re.sub(r'/\*.*?\*/|//[^\n]*|@?"(?:\\.|[^"\\])*"', ' ', source, flags=re.S)


def luminance(rgb):
    channels = [(rgb >> shift & 255) / 255 for shift in (16, 8, 0)]
    linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in channels]
    return sum(v * weight for v, weight in zip(linear, (.2126, .7152, .0722)))


def contrast(foreground, background):
    a, b = sorted((luminance(foreground), luminance(background)))
    return (b + .05) / (a + .05)


def check(ui, components, dialog=''):
    component_code = code_only(components)
    all_code = '\n'.join(code_only(source) for source in (ui, components, dialog))
    definitions = list(TOKEN.finditer(component_code))
    palette = {}
    for match in definitions:
        name, light, dark = match.groups()
        assert name not in palette, 'Duplicate palette definition: ' + name
        # Remove the definition before counting: an export declaration, comment,
        # or a dead legacy alias is not evidence of a rendered semantic token.
        usage = all_code.replace(match.group(), '', 1)
        assert re.search(r'\b' + re.escape(name) + r'\s*\(', usage), 'Unused palette function: ' + name
        palette[name] = (int(light, 16), int(dark, 16))
    exports = set(re.findall(r'(?m)^UIColor\s*\*\s*(QHV\w+Color)\(void\)', component_code))
    assert exports == PUBLIC, ('Shared semantic token exports changed', sorted(exports))
    assert PUBLIC <= palette.keys(), 'A public semantic token is not an opaque VColor definition'
    assert {'VHero', 'VGood', 'VGoodBackground', 'VAttention', 'VAttentionBackground'} <= palette.keys()
    provider = component_code.split('static UIColor *VColor(', 1)[1].split('UIColor *QHVBackgroundColor', 1)[0]
    assert 'colorWithDynamicProvider:' in provider and 'UIUserInterfaceStyleDark ? dark : light' in provider
    assert re.search(r'alpha\s*:\s*1\s*\]', provider), 'Opaque contrast requires alpha 1 in VColor'
    for mode in (0, 1):
        for foreground, background in PAIRS:
            ratio = contrast(palette[foreground][mode], palette[background][mode])
            assert ratio >= 4.5, (foreground, background, 'light' if mode == 0 else 'dark', ratio)
    return palette


def recolor(source, name, light=None, dark=None):
    """Mutate a named token, independent of yesterday's hexadecimal snapshot."""
    matches = [match for match in TOKEN.finditer(source) if match.group(1) == name]
    assert len(matches) == 1, 'Mutation target missing/duplicated: ' + name
    match = matches[0]
    replacement = match.group().replace('0x' + match.group(2), f'0x{light:06x}', 1) if light is not None else match.group()
    if dark is not None:
        replacement = replacement.replace('0x' + match.group(3), f'0x{dark:06x}', 1)
    changed = source[:match.start()] + replacement + source[match.end():]
    assert changed != source, 'Mutation did not change ' + name
    return changed


def rejected(ui, components, dialog):
    try:
        check(ui, components, dialog)
    except AssertionError:
        return
    raise AssertionError('Unsafe palette mutation was accepted')


def main():
    ui = (ROOT / 'App/QHAppController.m').read_text(encoding='utf-8')
    components = (ROOT / 'App/QHVisualComponents.m').read_text(encoding='utf-8')
    dialog = (ROOT / 'App/QHDialogController.m').read_text(encoding='utf-8')
    palette = check(ui, components, dialog)
    mutations = [
        recolor(components, 'QHVSecondaryTextColor', light=0x9a93a6),
        recolor(components, 'VHero', dark=palette['QHVSecondaryTextColor'][1]),
        recolor(components, 'VGoodBackground', light=palette['VGood'][0]),
        recolor(components, 'VAttentionBackground', dark=palette['VAttention'][1]),
        components.replace('alpha:1]', 'alpha:0.7]', 1),
        components + '\nstatic UIColor *VUnusedTile(void) { return VColor(0xede8fb, 0x332d4d); }\n',
    ]
    for changed in mutations:
        assert changed != components
        rejected(ui, changed, dialog)
    for mode in (0, 1):
        ratios = [contrast(palette['QHVSecondaryTextColor'][mode], palette[name][mode]) for name in SURFACES]
        print(('Light' if mode == 0 else 'Dark') + ' secondary text / background-card-inner-hero: ' +
              ', '.join(f'{value:.2f}:1' for value in ratios))
    print(f'Palette source: {len(PAIRS) * 2} opaque >=4.5:1 contrast pairs + {len(mutations)} rejected mutations PASS')
    # Keep the existing release-version safety signal. validate.py deliberately
    # validates real locale coverage first; missing parent-owned locale keys
    # must fail, not be ignored just to reach the version rejection.
    release = subprocess.run([sys.executable, str(ROOT / 'scripts/validate.py'), '--release'],
                             capture_output=True, text=True, encoding='utf-8')
    assert release.returncode != 0 and 'Formal release version must be numeric' in release.stderr, release.stderr
    print('Test package version rejected as formal release PASS; actual UIKit/VoiceOver acceptance remains CI/device-only.')


if __name__ == '__main__':
    main()
