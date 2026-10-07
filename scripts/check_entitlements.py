import plistlib,sys
from pathlib import Path
actual=plistlib.loads(Path(sys.argv[1]).read_bytes())
expected=plistlib.loads(Path(sys.argv[2]).read_bytes())
if actual!=expected:raise SystemExit('Signed entitlement data does not equal intended scope')
print('Signed entitlements match exact source scope')
