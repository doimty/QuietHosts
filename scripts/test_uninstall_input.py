#!/usr/bin/env python3
"""Both prerm input chains; macOS additionally executes production ReadRequest."""
import argparse, hashlib, json, os, pathlib, shlex, subprocess, sys, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
# Exact native13 prerm bytes, so CI's shallow checkout needs no ancestor objects.
BASE_PRERM_SHA256 = {
    'roothide': 'fc578fb181308052653aa10478dfb1dc0284f575309ed697e42d10b10c8abe1d',
    'rootless': 'ac34a8d46eaebe542b92cb18bd136a553ebc0d7369b4dbce1f30950925d45ab0',
}
CASES = [('remove', 0), ('deconfigure', 0), ('remove', 1), ('deconfigure', 1),
         ('remove', 42), ('upgrade', 0), ('failed-upgrade', 0), (None, 0)]


def script_for(scheme):
    folder = 'layout' if scheme == 'roothide' else 'layout-rootless'
    path = folder + '/DEBIAN/prerm'
    helper = ('/var/jb' if scheme == 'rootless' else '') + '/usr/libexec/quiethosts-helper'
    current = (ROOT/path).read_text()
    old = helper + ' restore-for-uninstall </dev/null'
    new = "printf '%s\\n' '{}' | " + helper + ' restore-for-uninstall'
    assert current.count(new) == 1 and '</dev/null' not in current
    projected = current.replace(new, old, 1)
    assert hashlib.sha256(projected.encode()).hexdigest() == BASE_PRERM_SHA256[scheme], 'Only stdin feed may change'
    subprocess.run(['sh', '-n', str(ROOT/path)], check=True)
    return current, helper


def run_cases(temp, helper, scheme, phase):
    text, fixed = script_for(scheme)
    script = temp/(scheme+'-'+phase+'.sh')
    script.write_text(text.replace(fixed, shlex.quote(str(helper)), 1))
    results = []
    for action, code in CASES:
        env = dict(os.environ, QH_FIXTURE_EXIT=str(code))
        run = subprocess.run(['sh', str(script)] + ([] if action is None else [action]),
                             capture_output=True, text=True, env=env, timeout=25)
        called = action in ('remove', 'deconfigure')
        expected = 1 if called and code else 0
        assert run.returncode == expected, (scheme, phase, action, code, run.stdout, run.stderr)
        if called:
            reply = json.loads(run.stdout)
            assert reply['request'] == {} and reply['stdinPipe'] is True
            assert reply['ok'] == (code == 0), reply
            if code:
                assert 'checked restore failed' in run.stderr and reply['errorCode']
            else:
                assert not run.stderr
        else:
            assert not run.stdout and not run.stderr
        results.append({'scheme': scheme, 'phase': phase, 'action': action,
                        'helper_exit': code, 'prerm_exit': run.returncode, 'pass': True})
    return results


def production_input_source():
    source = (ROOT/'Helper/main.m').read_text()
    start = source.index('static NSDictionary *ReadRequest(')
    end = source.index('\n/* Fixed executable', start)
    reader = source[start:end]
    mono = source[source.index('static double Monotonic('):source.index('static NSDictionary *Failure(')]
    limit = next(line for line in source.splitlines() if line.startswith('static const NSUInteger InputLimit ='))
    return limit+'\n'+mono+'\n'+reader


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    rows = []
    with tempfile.TemporaryDirectory(prefix='qh-uninstall-input-') as folder:
        temp = pathlib.Path(folder)
        fake = temp/'fake-helper'
        fake.write_text('''#!/usr/bin/env python3
import json, os, stat, sys
assert sys.argv[1:] == ['restore-for-uninstall']
payload = sys.stdin.buffer.read(1024)
assert payload == b'{}\\n' and stat.S_ISFIFO(os.fstat(0).st_mode)
code = int(os.environ['QH_FIXTURE_EXIT'])
print(json.dumps({'ok': code == 0, 'request': json.loads(payload), 'stdinPipe': True,
                  'errorCode': 'fixture-restore-conflict' if code else ''}))
raise SystemExit(code)
''')
        fake.chmod(0o755)
        for scheme in ('roothide', 'rootless'):
            rows.extend(run_cases(temp, fake, scheme, 'fake-helper'))
        core = production_input_source()
        native_control = None
        if sys.platform == 'darwin':
            driver = temp/'input-driver.m'
            driver.write_text('''#import <Foundation/Foundation.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
''' + core + '''
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2 || strcmp(argv[1], "restore-for-uninstall")) return 93;
        NSString *error = nil;
        NSDictionary *request = ReadRequest(YES, &error);
        int code = request ? 0 : 1;
        const char *forced = getenv("QH_FIXTURE_EXIT");
        if (request && forced) code = (int)strtol(forced, NULL, 10);
        if (request && code) error = @"fixture-restore-conflict";
        struct stat st;
        BOOL pipe = fstat(STDIN_FILENO, &st) == 0 && S_ISFIFO(st.st_mode);
        NSDictionary *reply = @{@"ok": @(code == 0), @"request": request ?: @{},
                                @"stdinPipe": @(pipe), @"errorCode": error ?: @""};
        NSData *data = [NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL];
        if (!data) return 94;
        fwrite(data.bytes, 1, data.length, stdout); putchar('\\n');
        return code;
    }
}
''')
            binary = temp/'input-driver'
            subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-Wall', '-Wextra',
                            '-Werror', '-framework', 'Foundation', str(driver), '-o', str(binary)],
                           check=True, timeout=180)
            for scheme in ('roothide', 'rootless'):
                rows.extend(run_cases(temp, binary, scheme, 'production-ReadRequest'))
            with open(os.devnull, 'rb') as null:
                env = dict(os.environ, QH_FIXTURE_EXIT='0')
                run = subprocess.run([str(binary), 'restore-for-uninstall'], stdin=null,
                                     capture_output=True, text=True, env=env, timeout=25)
            native_control = {'returncode': run.returncode, 'reply': json.loads(run.stdout)}
        report = {'scope': 'isolated production prerm projection; no real helper/Hosts/DNS/restore writes',
                  'cases': rows, 'read_request_sha256': hashlib.sha256(core.encode()).hexdigest(),
                  'foundation': 'executed' if sys.platform == 'darwin' else 'SKIP: macOS/Xcode required',
                  'devnull_control': native_control, 'device_executed': False}
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report, indent=2))

if __name__ == '__main__':
    main()
