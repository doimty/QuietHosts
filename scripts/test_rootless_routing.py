#!/usr/bin/env python3
"""Execute production routing code; a compiler failure is never mutation evidence."""
import json, shutil, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PROD=ROOT/'Helper/QHRootlessRouting.c'
LAYOUT=ROOT/'Helper/QHRootlessLayout.c'
TEST=ROOT/'Tests/RootlessRoutingTests.c'
FLAGS=['-std=c11','-D_GNU_SOURCE','-D_DARWIN_C_SOURCE','-Wall','-Wextra','-Werror','-I'+str(ROOT/'Helper')]
def run(cc,source,out,name,extra=()):
    exe=out/(name+'.bin')
    subprocess.run([cc,*FLAGS,*extra,str(source),str(LAYOUT),str(TEST),'-o',str(exe)],check=True)
    fixture=out/(name+'.fixture');fixture.mkdir(mode=0o755)
    return subprocess.run([str(exe),str(fixture)],capture_output=True,text=True)
def main():
    results={'scope':'host production C execution, NOT rootless iOS acceptance','positive':[],'mutations':[]}
    with tempfile.TemporaryDirectory(prefix='qh-route-') as temp:
        folder=Path(temp)
        compilers=[cc for cc in ('cc','clang') if shutil.which(cc)]
        if not compilers: raise SystemExit('No C compiler')
        for cc in compilers:
            got=run(cc,PROD,folder,cc);assert got.returncode==0,(got.stdout,got.stderr)
            results['positive'].append({'compiler':cc,'result':got.stdout.strip()})
        text=PROD.read_text()
        mutations={
            'alias_text_guard_removed':('if (strcmp(target, wanted) != 0) goto cleanup;','/* mutant: ignore dependency alias */'),
            'alias_identity_guard_removed':('if (!AliasSame(&routing->alias, &alias))','if (0)'),
            'ancestor_protection_removed':('return fstat(fd, &st) == 0 && QHProtectedDirectoryAllowed(&st, owner, 0);','(void)owner; return fstat(fd, &st) == 0 && S_ISDIR(st.st_mode);'),
        }
        for name,(old,new) in mutations.items():
            assert text.count(old)==1,(name,'mutation anchor drift')
            source=folder/(name+'.c');source.write_text(text.replace(old,new))
            got=run(compilers[0],source,folder,name)
            assert got.returncode!=0 and 'FAIL:' in got.stderr,(name,got.stdout,got.stderr)
            results['mutations'].append({'name':name,'rejected':True})
        if shutil.which('clang'):
            got=run('clang',PROD,folder,'ubsan',['-fsanitize=undefined','-fno-sanitize-recover=all'])
            assert got.returncode==0,(got.stdout,got.stderr)
            results['ubsan']=got.stdout.strip()
    print(json.dumps(results,indent=2))
    return results
if __name__=='__main__': main()
