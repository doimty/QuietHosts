"""Native C read-only preflight tests; isolated fixtures, no Apple cross-build."""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Helper/QHRootlessLayout.c'
TEST = ROOT / 'Tests/RootlessLayoutTests.c'
FLAGS = ['-std=c11', '-D_POSIX_C_SOURCE=200809L', '-D_DARWIN_C_SOURCE',
         '-Wall', '-Wextra', '-Werror', '-I', str(ROOT / 'Helper')]


def execute(cc, source, directory, extra=()):
    binary = directory / 'layout-test'
    compiled = subprocess.run([cc, *FLAGS, *extra, str(source), str(TEST), '-o', str(binary)],
                              capture_output=True, text=True)
    if compiled.returncode:
        raise RuntimeError('Compilation is not mutation evidence:\n' + compiled.stderr)
    fixture = directory / 'fixture'
    fixture.mkdir()
    return subprocess.run([str(binary), str(fixture)], capture_output=True, text=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    compilers = [cc for cc in ('cc', 'clang') if shutil.which(cc)]
    assert compilers, 'No native C compiler; cannot claim execution'
    source = SOURCE.read_text()
    assert not re.search(r'\b(mkdir(?:at)?|unlink(?:at)?|rename(?:at)?|write|symlink(?:at)?|fork|execv|system)\s*\(', source), 'Production preflight must be read-only'
    results = {'scope': 'native host C fixture execution, NOT iOS acceptance',
               'positive': [], 'mutations': []}
    for cc in compilers:
        with tempfile.TemporaryDirectory(prefix='qh-rootless-layout-') as temporary:
            done = execute(cc, SOURCE, pathlib.Path(temporary))
            assert done.returncode == 0, (cc, done.stdout, done.stderr)
            results['positive'].append({'compiler': cc, 'result': done.stdout.strip()})
    variants = {
        'mobile_root_exception': source.replace(
            'QHProtectedDirectoryAllowed(entry, owner, 0)',
            'QHContainerRootAllowed(entry, owner)'),
        'root_alias_guard_removed': source.replace(
            'if (SameIdentity(&found.root, &found.system))', 'if (0)'),
        'symlink_follow_enabled': source.replace('AT_SYMLINK_NOFOLLOW', '0').replace(
            'O_NOFOLLOW | ', ''),
    }
    for name, changed in variants.items():
        assert changed != source, ('Mutation did not apply', name)
        with tempfile.TemporaryDirectory(prefix='qh-rootless-mutation-') as temporary:
            directory = pathlib.Path(temporary)
            mutant = directory / 'layout-mutant.c'
            mutant.write_text(changed)
            done = execute(compilers[0], mutant, directory)
            # A compile error is NOT mutation evidence. execute() raises on it.
            assert done.returncode != 0 and 'FAIL:' in done.stderr, (
                'Behavior mutation escaped the actual C tests', name, done.stdout)
            results['mutations'].append({'name': name, 'rejected': True})
    if shutil.which('clang'):
        with tempfile.TemporaryDirectory(prefix='qh-rootless-ubsan-') as temporary:
            done = execute('clang', SOURCE, pathlib.Path(temporary),
                           ['-fsanitize=undefined', '-fno-sanitize-recover=all'])
            assert done.returncode == 0, (done.stdout, done.stderr)
            results['ubsan'] = done.stdout.strip()
    text = json.dumps(results, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
    print(text, end='')


if __name__ == '__main__':
    main()
