#!/usr/bin/env python3
"""RootHide official aliases plus real read-only target identity; host-only."""
import argparse, json, os, pathlib, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]


def wiring(text):
    for label in ('CAPTURE', 'RECHECK'):
        begin = f'/* QH_PAIR_TARGET_{label}_BEGIN */\n'
        end = f'/* QH_PAIR_TARGET_{label}_END */\n'
        assert text.count(begin) == text.count(end) == 1
        block = text.split(begin, 1)[1].split(end, 1)[0]
        assert '#if !defined(QH_ROOTLESS) || !QH_ROOTLESS' in block
        for call in ('QHPairedLinkTargetMatches(_privateFD, "var", &_varAnchor)',
                     'QHPairedLinkTargetMatches(_pairRootFD, ".jbroot", &_rootAnchor)'):
            assert call in block, (label, call)
        assert 'AT_SYMLINK_NOFOLLOW' in block and 'SameStat(' in block


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    manager = (ROOT/'Helper/QHFileManager.m').read_text()
    wiring(manager)
    wiring_mutations = []
    for label in ('CAPTURE', 'RECHECK'):
        begin = f'/* QH_PAIR_TARGET_{label}_BEGIN */\n'
        end = f'/* QH_PAIR_TARGET_{label}_END */\n'
        a = manager.index(begin); b = manager.index(end, a)
        for call in ('QHPairedLinkTargetMatches(_privateFD, "var", &_varAnchor)',
                     'QHPairedLinkTargetMatches(_pairRootFD, ".jbroot", &_rootAnchor)'):
            changed = manager[:a] + manager[a:b].replace(call, '1', 1) + manager[b:]
            try:
                wiring(changed)
            except AssertionError:
                wiring_mutations.append({'phase': label, 'call': call, 'rejected': True})
            else:
                raise AssertionError('Missing target guard was accepted')
    header = (ROOT/'Helper/QHDirectoryPolicy.h').read_text()
    assert header.count('QHPlatformRootFSPath(native)') == 2
    anchor = 'int matches = fstat(fd, &actual) == 0 && QHDirectoryAnchorMatches(&actual, expected);'
    assert header.count(anchor) == 1
    tests = (ROOT/'Tests/DirectoryPolicyTests.c').read_text()
    compilers = list(dict.fromkeys([os.environ.get('CC', 'cc'), 'clang']))
    results = []
    with tempfile.TemporaryDirectory(prefix='qh-alias-identity-') as directory:
        tmp = pathlib.Path(directory)
        (tmp/'Helper').mkdir(); (tmp/'Tests').mkdir()
        (tmp/'Tests/policy.c').write_text(tests)
        for compiler in compilers:
            for mutant in (False, True):
                source = header.replace(anchor, 'int matches = fstat(fd, &actual) == 0;', 1) if mutant else header
                (tmp/'Helper/QHDirectoryPolicy.h').write_text(source)
                binary = tmp/('mutant' if mutant else 'test')
                command = [compiler, '-std=c11', '-D_DEFAULT_SOURCE', '-Wall', '-Wextra', '-Werror',
                           str(tmp/'Tests/policy.c'), '-o', str(binary)]
                subprocess.run(command, check=True, timeout=60)
                run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
                if mutant:
                    assert run.returncode == 1, run.stdout+run.stderr
                    assert 'FAIL: wrong target identity is rejected' in run.stderr
                    assert 'FAIL: valid spelling alone cannot authorize foreign target' in run.stderr
                else:
                    assert run.returncode == 0, run.stdout+run.stderr
                results.append({'compiler': compiler, 'mutant': mutant, 'expected_result_observed': True})
        (tmp/'Helper/QHDirectoryPolicy.h').write_text(header)
        binary = tmp/'ubsan'
        subprocess.run(['clang', '-std=c11', '-D_DEFAULT_SOURCE', '-Wall', '-Wextra', '-Werror',
                        '-fsanitize=undefined', '-fno-sanitize-recover=all',
                        str(tmp/'Tests/policy.c'), '-o', str(binary)], check=True, timeout=60)
        subprocess.run([str(binary)], check=True, timeout=60)
    report = {'scope': 'production C + real isolated symlink/fstat execution; NOT Apple Foundation or iOS acceptance',
              'runs': results, 'ubsan': 'PASS', 'removed_wiring_mutations': wiring_mutations,
              'rootfs_call_sites': 2, 'device_executed': False, 'foundation_executed': False}
    if args.output:
        args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    main()
