"""Source-derived opaque palette checks, not UIKit/accessibility runtime acceptance."""
from pathlib import Path
import re, subprocess, sys
ROOT = Path(__file__).resolve().parents[1]

def luminance(rgb):
    channels = [(rgb >> shift & 255) / 255 for shift in (16, 8, 0)]
    linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in channels]
    return sum(v * weight for v, weight in zip(linear, (.2126, .7152, .0722)))

def contrast(foreground, background):
    a, b = sorted((luminance(foreground), luminance(background)))
    return (b + .05) / (a + .05)

def check(ui, components):
    palette = {}
    for source, color_function in ((ui, 'Color'), (components, 'VColor')):
        for name, light, dark in re.findall(r'static UIColor \*(\w+)\(void\) \{\s*return '+color_function+r'\(0x([0-9a-f]+), 0x([0-9a-f]+)\);\s*\}', source):
            assert len(re.findall(r'\b' + name + r'\s*\(', source)) > 1, 'Unused palette function: ' + name
            palette[name] = (int(light, 16), int(dark, 16))
    assert palette['CardBackground'] == palette['VCard']
    assert palette['Accent'] == palette['VAccent']
    assert palette['TextPrimary'] == palette['VText']
    assert palette['TextSecondary'] == palette['VSecondary']
    palette['CardSecondaryBackground'] = palette['VInner']
    for mode in (0, 1):
        for foreground in ('TextPrimary', 'TextSecondary', 'Accent'):
            for background in ('Background', 'CardBackground', 'CardSecondaryBackground'):
                ratio = contrast(palette[foreground][mode], palette[background][mode])
                assert ratio >= 4.5, (foreground, background, mode, ratio)
        for foreground, background in (('VAccent','VTile'), ('VGood','VGoodBackground'), ('VDanger','VDangerBackground'), ('VDanger','VCard')):
            assert contrast(palette[foreground][mode], palette[background][mode]) >= 4.5, (foreground, background, mode)
        ratio = contrast((0xffffff, 0x13131a)[mode], palette['Accent'][mode])
        assert ratio >= 4.5, ('filled button', mode, ratio)
    return palette

def main():
    ui = (ROOT / 'App/QHAppController.m').read_text()
    components = (ROOT / 'App/QHVisualComponents.m').read_text()
    palette = check(ui, components)
    old = ui.replace('Color(0x686875, 0x9e9ea8)', 'Color(0x8b8b96, 0x9e9ea8)')
    assert old != ui
    try:
        check(old, components)
    except AssertionError:
        pass
    else:
        raise AssertionError('Old low-contrast palette was accepted')
    unused = ui + '\nstatic UIColor *UnusedTile(void) { return Color(0xedebfa, 0x2b2944); }\n'
    try:
        check(unused, components)
    except AssertionError:
        pass
    else:
        raise AssertionError('Unused palette function was accepted')
    release = subprocess.run([sys.executable, str(ROOT/'scripts/validate.py'), '--release'], capture_output=True, text=True)
    assert release.returncode != 0 and 'Formal release version must be numeric' in release.stderr
    for mode in (0, 1):
        ratios = [contrast(palette['TextSecondary'][mode], palette[name][mode]) for name in ('Background', 'CardBackground', 'CardSecondaryBackground')]
        print(('Light' if mode == 0 else 'Dark') + ' secondary text contrast: ' + ', '.join(f'{v:.2f}:1' for v in ratios))
    print('Palette: 28 opaque contrast pairs + 2 rejected mutations; test version rejected as formal release PASS')
if __name__ == '__main__':
    main()
