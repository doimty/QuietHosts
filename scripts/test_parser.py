#!/usr/bin/env python3
"""Compile/run actual C parser, then optionally diagnose read-only user corpora.
No user converters executed; generated pair snapshots are test oracles in memory,
NOT execution of the Foundation generator (covered by RunRuleEngineTests on macOS).
Usage: python3 scripts/test_parser.py [--sanitize] [corpus ...]
"""
import argparse
import ctypes as C
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ('lines ignoredLines redirectLines invalidLines invalidNames localNames '
          'acceptedNames unsupported firstRejectedLine').split()

class Stats(C.Structure):
    _fields_ = [(name, C.c_size_t) for name in FIELDS]

CONSUMER = C.CFUNCTYPE(C.c_bool, C.c_char_p, C.c_void_p)

def run(args):
    print('+', ' '.join(map(str, args)), flush=True)
    subprocess.run(args, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sanitize', action='store_true')
    parser.add_argument('corpus', nargs='*', type=Path)
    args = parser.parse_args()
    compilers = [shutil.which(c) for c in ('gcc', 'clang')]
    compilers = list(dict.fromkeys(c for c in compilers if c))
    if not compilers:
        raise SystemExit('C compiler required')
    with tempfile.TemporaryDirectory(prefix='quiethosts-parser-') as tmp:
        tmp = Path(tmp)
        for index, compiler in enumerate(compilers):
            flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-O2']
            if args.sanitize:
                flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
            exe = tmp / f'tests-{index}'
            run([compiler, *flags, ROOT/'Shared/QHParser.c', ROOT/'Tests/ParserTests.c', '-o', exe])
            run([exe])
        library = tmp / 'libqhparser.so'
        run([compilers[0], '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-O2',
             '-shared', '-fPIC', ROOT/'Shared/QHParser.c', '-o', library])
        lib = C.CDLL(str(library))
        lib.QHParserParse.argtypes = [C.c_void_p, C.c_size_t, C.c_bool, CONSUMER, C.c_void_p, C.POINTER(Stats)]
        lib.QHParserParse.restype = C.c_int

        def parse(raw, allow=False, cap=300000):
            names = set()
            duplicates = 0
            @CONSUMER
            def consume(name, _):
                nonlocal duplicates
                if name in names:
                    duplicates += 1
                    return True
                if len(names) == cap:
                    return False
                names.add(bytes(name))
                return True
            stats = Stats()
            buf = C.create_string_buffer(raw)
            status = lib.QHParserParse(buf, len(raw), allow, consume, None, C.byref(stats))
            assert buf.raw[:-1] == raw, 'input was modified'
            return status, names, duplicates, {f: getattr(stats, f) for f in FIELDS}

        # Large actual-parser workload, bounded consumer rollback is caller-owned.
        raw = b''.join(f'n{i:06}.example\n'.encode() for i in range(300000))
        status, names, duplicates, stats = parse(raw)
        assert status == 0 and len(names) == 300000 and stats['acceptedNames'] == 300000
        assert parse(raw + b'n000000.example\n')[2] == 1
        assert parse(raw + b'extra.example\n')[0] == 3
        assert parse(raw + b'\0')[0] == 2
        assert parse(b'#' + b' ' * (16*1024*1024-1))[0] == 0
        assert parse(b'#' + b' ' * (16*1024*1024))[0] == 1
        assert parse(b'valid.example\n0.0.0.0 bad.example', True)[0] == 4
        # Exhaustive byte mutations in fields never emit a hostname containing
        # non-ASCII/control/unsupported bytes; encoding failures emit nothing.
        for value in range(256):
            status, names, _, _ = parse(b'good.example\n' + bytes([value]) + b'bad.example\n')
            if status == 2:
                assert not names
            for name in names:
                assert all(c in b'abcdefghijklmnopqrstuvwxyz0123456789-.' for c in name)
        print('Large C-parser tests: PASS (300000, +1, duplicate, UTF8 preflight, 16MiB, mutations)', flush=True)
        merged = set()
        total_bytes = 0
        reports = []
        for path in args.corpus:
            raw = path.read_bytes()
            before = hashlib.sha256(raw).hexdigest()
            status, names, duplicates, stats = parse(raw)
            after = hashlib.sha256(path.read_bytes()).hexdigest()
            assert before == after
            report = dict(file=path.name, bytes=len(raw), sha256=before, unchanged=True,
                          status=status, unique=len(names), duplicates=duplicates, **stats)
            if status == 0:
                total_bytes += len(raw)
                merged.update(names)
                # Independent reference snapshot, no rewrite of original corpus.
                snapshot = b''.join(b'0.0.0.0 '+n+b'\n::1 '+n+b'\n' for n in sorted(names))
                report.update(referenceBlockBytes=len(snapshot),
                              referenceBlockSHA256=hashlib.sha256(snapshot).hexdigest(),
                              referenceBlockWithinLimit=len(snapshot) <= 32*1024*1024)
            reports.append(report)
            print(json.dumps(report, ensure_ascii=False, sort_keys=True), flush=True)
        if reports:
            snapshot = b''.join(b'0.0.0.0 '+n+b'\n::1 '+n+b'\n' for n in sorted(merged))
            print(json.dumps(dict(mergedUnique=len(merged), totalInputBytes=total_bytes,
                                  referenceBlockBytes=len(snapshot),
                                  referenceBlockSHA256=hashlib.sha256(snapshot).hexdigest(),
                                  withinLimits=len(merged) <= 300000 and total_bytes <= 32*1024*1024 and
                                  len(snapshot) <= 32*1024*1024), sort_keys=True))
    print('All local parser checks passed. Native Foundation tests still require macOS CI.')

if __name__ == '__main__':
    main()
