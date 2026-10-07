# Copyright (c) 2026 doimty. SPDX-License-Identifier: MIT
import argparse
from pathlib import Path
import os, shutil, plistlib
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);a=p.parse_args()
s=a.stage.resolve()
if s==Path('/') or not (s/'Applications/QuietHosts.app/QuietHosts').is_file():raise SystemExit('Refusing unexpected staging directory')
helper=s/'usr/libexec/quiethosts-helper'
if not helper.is_file():raise SystemExit('Missing helper')
os.chmod(helper,0o4755)
doc=s/'usr/share/doc/com.doimty.quiethosts';doc.mkdir(parents=True,exist_ok=True)
for name in ('LICENSE','THIRD_PARTY_NOTICES.md'):shutil.copyfile(ROOT/name,doc/name)
for locale in ('en','zh-Hans'):
 source=ROOT/'App/Resources'/f'{locale}.lproj/Localizable.strings'
 for bundle in (s/'Applications/QuietHosts.app',s/'Library/ControlCenter/Bundles/QuietHostsModule.bundle'):
  dest=bundle/f'{locale}.lproj/Localizable.strings';dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,dest)
print('Staged helper permissions and notices; no device commands executed.')
