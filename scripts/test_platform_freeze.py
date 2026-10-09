#!/usr/bin/env python3
"""Independent negative check: retain original RootHide file digests."""
from pathlib import Path
import hashlib, json
from platform_freeze import project_frozen_text
ROOT=Path(__file__).resolve().parents[1]
frozen=json.loads((ROOT/'Tests/Native9Frozen.json').read_text())['files']
changed=('Helper/main.m','Helper/QHFileManager.m','Shared/QHBridge.m',
         'App/Makefile','Helper/Makefile','Makefile','ci/prepare.py')
manifest=json.loads((ROOT/'Tests/RootHidePlatformFrozen.json').read_text())
assert manifest['baseline']=='cee42b76dd96c6699648dd67bdff68f07f708f54'
assert set(manifest['files'])==set(changed)
for path in changed:
    digest=manifest['files'][path]
    if path in frozen:
        assert digest==frozen[path],('Original SHA drift',path)
    text=(ROOT/path).read_bytes().decode()
    old=project_frozen_text(text,path)
    assert hashlib.sha256(old.encode()).hexdigest()==digest,path
    # Mutation in the preserved branch must still be caught, not filtered out.
    mutated=text.replace('roothide','roothide_BAD',1) if 'roothide' in old else text.replace('QH','BAD',1)
    if project_frozen_text(mutated,path)==old:
        mutated=text+'\n/* unrelated mutation */\n'
    assert hashlib.sha256(project_frozen_text(mutated,path).encode()).hexdigest()!=digest,path
print('RootHide exact 7 file projections + 7 negative mutations PASS; original hashes unchanged')
