from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
# Reuse the mature MIT checker with project name substitution; source is shipped
# alongside this wrapper as localization_core.py.
from localization_core import parse_strings, extract_literals, placeholders

def check():
 resources=ROOT/'App/Resources'
 locales={name:parse_strings((resources/(name+'.lproj')/'Localizable.strings').read_text()) for name in ('en','zh-Hans')}
 assert locales['en'].keys()==locales['zh-Hans'].keys(),'Locale keys differ'
 for k,v in locales['zh-Hans'].items():assert placeholders(k)==placeholders(v),f'Placeholder mismatch {k}'
 calls=0
 for folder in ('App','Shared','Module','Helper'):
  for p in (ROOT/folder).rglob('*'):
   if p.suffix not in ('.m','.h','.c'):continue
   for item in extract_literals(p.read_text().replace('QHL(', 'NSL(')):
    # Checker yields decoded literal and source line.
    key=item[0] if isinstance(item,tuple) else item
    assert key in locales['en'],f'Missing locale {p}: {key}'
    calls+=1
 print(f'Localization passed: {len(locales["en"])} bilingual keys, {calls} literal lookups.')
if __name__=='__main__':check()
