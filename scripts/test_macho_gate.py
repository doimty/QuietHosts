#!/usr/bin/env python3
"""Pure-stdlib, cross-platform validate.macho fixtures; no tar/chmod/staging.

Synthetic signatures exercise LC_CODE_SIGNATURE presence/range only. These are
not Apple builds, full codesign verification, setuid tests or device acceptance.
"""
from pathlib import Path
import json
import struct
import tempfile

from validate import macho

CPU_ARM64 = 0x100000c
ROOTLESS_RPATHS = ('/var/jb/usr/lib', '@loader_path/.jbroot/usr/lib')
DYLIB_COMMANDS = (0xc, 0x80000018, 0x8000001f, 0x20, 0x80000023)


def version(minimum=15 << 16, platform=2, tools=()):
    return struct.pack('<6I', 0x32, 24 + 8 * len(tools), platform, minimum,
                       0x100500, len(tools)) + b''.join(struct.pack('<2I', *tool) for tool in tools)


def path_command(cmd, name):
    data = name.encode('utf-8') + b'\0'
    base = 12 if cmd == 0x8000001c else 24
    size = (base + len(data) + 7) // 8 * 8
    header = struct.pack('<3I', cmd, size, base)
    if base == 24:
        header += struct.pack('<3I', 0, 0, 0)
    return header + data + b'\0' * (size - base - len(data))


def image(scheme, commands, *, cpu=CPU_ARM64, subtype=None, kind=2, signed=True):
    commands = list(commands)
    # Empty SuperBlob, intentionally without CodeDirectory/hashes/entitlements.
    signature = struct.pack('>3I', 0xfade0cc0, 12, 0) if signed else b''
    if signed:
        offset = 32 + sum(map(len, commands)) + 16
        commands.append(struct.pack('<4I', 0x1d, 16, offset, len(signature)))
    area = b''.join(commands)
    if subtype is None:
        subtype = 0x80000002 if scheme == 'roothide' else 0
    header = struct.pack('<8I', 0xfeedfacf, cpu, subtype, kind,
                         len(commands), len(area), 0, 0)
    return header + area + signature


def binary(scheme, *, minimum=15 << 16, platform=2, deps=(), rpaths=None,
           cpu=CPU_ARM64, subtype=None, kind=2, signed=True, legacy=False):
    commands = [struct.pack('<4I', 0x25, 16, minimum, 0x100500) if legacy
                else version(minimum, platform)]
    if rpaths is None:
        rpaths = ROOTLESS_RPATHS if scheme == 'rootless' else ()
    commands.extend(path_command(0x8000001c, name) for name in rpaths)
    commands.extend(path_command(0xc, name) for name in deps)
    return image(scheme, commands, cpu=cpu, subtype=subtype, kind=kind, signed=signed)


def word(raw, offset, value):
    changed = bytearray(raw)
    struct.pack_into('<I', changed, offset, value)
    return bytes(changed)


def command_position(raw, wanted):
    # Called only on intact fixture bytes, independently of the validator.
    pos = 32
    for _ in range(struct.unpack_from('<I', raw, 16)[0]):
        cmd, size = struct.unpack_from('<2I', raw, pos)
        if cmd == wanted:
            return pos
        pos += size
    raise AssertionError('Missing fixture command ' + hex(wanted))


def command_word(raw, cmd, offset, value):
    return word(raw, command_position(raw, cmd) + offset, value)


def string_mutation(raw, cmd, mode):
    changed = bytearray(raw)
    pos = command_position(raw, cmd)
    size, offset = struct.unpack_from('<2I', raw, pos + 4)
    start = pos + offset
    if mode == 'unterminated':
        changed[start:pos + size] = b'x' * (pos + size - start)
    elif mode == 'empty':
        changed[start] = 0
    elif mode == 'invalid utf8':
        changed[start] = 0xff
    else:
        raise AssertionError('Unknown string mutation')
    return bytes(changed)


def main():
    checks = 0
    cases = []

    def check(value, reason):
        nonlocal checks
        checks += 1
        if not value:
            raise AssertionError(reason)

    with tempfile.TemporaryDirectory(prefix='qh-macho-gate-') as temp:
        def case(scheme, name, raw, reason=None, filename='QuietHosts'):
            path = Path(temp) / filename
            path.write_bytes(raw)
            try:
                result = macho(path, scheme)
            except ValueError as error:
                check(reason is not None, name + ': unexpectedly rejected: ' + str(error))
                check(reason in str(error), name + ': wrong diagnostic: ' + str(error))
                cases.append({'scheme': scheme, 'case': name, 'file': filename,
                              'result': 'rejected', 'reason': str(error)})
            else:
                check(reason is None, name + ': unsafe fixture accepted')
                check(result['arch'] == ('arm64e' if scheme == 'roothide' else 'arm64'), name)
                check(result['minOS'] == '15.0', name)
                subtype = struct.unpack_from('<I', raw, 8)[0]
                check(result['cpusubtype'] == hex(subtype) and result['caps'] == hex(subtype >> 24), name)
                check('NOT full codesign verification' in result['signature'], name)
                cases.append({'scheme': scheme, 'case': name, 'file': filename,
                              'result': 'accepted'})
            # struct.error/IndexError and other unexpected failures deliberately
            # propagate: malformed inputs must be explicitly rejected, not crash.

        for scheme in ('roothide', 'rootless'):
            for filename in ('QuietHosts', 'quiethosts-helper'):
                case(scheme, 'valid thin executable', binary(scheme), filename=filename)
            case(scheme, 'valid legacy iOS minimum command', binary(scheme, legacy=True))
            case(scheme, 'wrong CPU', binary(scheme, cpu=0x1000007), 'Wrong CPU architecture')
            for minimum in (14 << 16, 16 << 16, (15 << 16) | 1):
                case(scheme, 'wrong minOS ' + hex(minimum), binary(scheme, minimum=minimum),
                     'Missing minOS/signature')
            case(scheme, 'simulator platform', binary(scheme, platform=7), 'Not iOS')
            case(scheme, 'missing signature', binary(scheme, signed=False), 'Missing minOS/signature')
            case(scheme, 'missing minimum command', image(scheme, []), 'Missing minOS/signature')
            case(scheme, 'AutoPatches dependency', binary(scheme, deps=('/Library/AutoPatches/bad.dylib',)),
                 'Wrong platform or compatibility library found')

        for filename in ('QuietHosts', 'quiethosts-helper'):
            case('roothide', 'arm64e caps0', binary('roothide', subtype=2),
                 'RootHide arm64e PAC capability missing', filename)
            case('rootless', 'wrong CPU subtype', binary('rootless', subtype=2),
                 'Wrong CPU architecture', filename)
        case('roothide', 'PAC with wrong base subtype', binary('roothide', subtype=0x80000000),
             'Wrong CPU architecture')
        for subtype in (1, 0x80000002):
            case('rootless', 'wrong CPU subtype ' + hex(subtype), binary('rootless', subtype=subtype),
                 'Wrong CPU architecture')
        case('rootless', 'PAC not required or prohibited for subtype0', binary('rootless', subtype=0x80000000))
        case('roothide', 'valid build tool table', image('roothide', [version(tools=((3, 0x100500),))]))
        for minimums in ((14 << 16, 15 << 16), (15 << 16, 16 << 16)):
            case('roothide', 'conflicting minOS commands ' + str(minimums),
                 image('roothide', [version(value) for value in minimums]), 'Missing minOS/signature')

        for paths in ((), ROOTLESS_RPATHS[:1], ROOTLESS_RPATHS[1:],
                      ('/var/jb/usr/lib/', ROOTLESS_RPATHS[1])):
            case('rootless', 'missing exact rpaths ' + str(paths), binary('rootless', rpaths=paths),
                 'Rootless rpath missing')
        for name in ('@loader_path/.jbroot/usr/lib/libroothide.dylib', '/usr/lib/bad.roothidepatch'):
            case('rootless', 'wrong environment dependency ' + name, binary('rootless', deps=(name,)),
                 'Wrong platform or compatibility library found')
        for cmd in DYLIB_COMMANDS:
            case('roothide', 'rootless dependency command ' + hex(cmd),
                 image('roothide', [version(), path_command(cmd, '/var/jb/usr/lib/libroot.dylib')]),
                 'Wrong platform or compatibility library found')
        case('roothide', 'rootless rpath', binary('roothide', rpaths=('/var/jb/usr/lib',)),
             'Wrong platform or compatibility library found')
        case('rootless', 'RootHide rpath', binary('rootless', rpaths=ROOTLESS_RPATHS + ('/usr/lib/libroothide',)),
             'Wrong platform or compatibility library found')
        case('rootless', 'valid paths including v2 rpath',
             binary('rootless', deps=('/var/jb/usr/lib/libroot.dylib', '/usr/lib/libSystem.B.dylib')))

        good = binary('roothide')
        case('roothide', 'truncated header', good[:31], 'Expected thin Mach-O')
        case('roothide', 'truncated command bytes', good[:40], 'Bad command area')
        case('roothide', 'truncated signature bytes', good[:-1], 'Bad signature')
        case('roothide', 'fat header', word(good, 0, 0xbebafeca), 'Expected thin Mach-O')
        case('roothide', 'wrong executable kind', binary('roothide', kind=6), 'Expected Mach-O executable')
        case('unknown', 'unknown scheme', good, 'Unknown platform scheme')
        case('roothide', 'command area beyond file', word(good, 20, len(good)), 'Bad command area')
        case('roothide', 'huge command count', word(good, 16, 0xffffffff), 'Bad command count')
        case('roothide', 'unconsumed command bytes', word(good, 16, 1), 'Bad command area')
        case('roothide', 'extra command count', word(good, 16, 3), 'Bad command area')
        for size in (0, 12, 0xfffffff8):
            case('roothide', 'bad command size ' + str(size), command_word(good, 0x32, 4, size), 'Bad command')
        for cmd, reason in ((0x32, 'Bad build version command'), (0x25, 'Bad minimum version command'),
                            (0x1d, 'Bad signature command'), (0xc, 'Bad dependency command'),
                            (0x8000001c, 'Bad rpath command')):
            case('roothide', 'truncated command ' + hex(cmd),
                 image('roothide', [struct.pack('<2I', cmd, 8)], signed=False), reason)
        for tools in (1, 0xffffffff):
            case('roothide', 'truncated build tools ' + str(tools), command_word(good, 0x32, 20, tools),
                 'Bad build version tools')
        for field, value, name in ((12, 0, 'zero signature length'), (8, len(good), 'signature past EOF'),
                                   (8, 32, 'signature overlaps commands'),
                                   (12, 0xffffffff, 'signature range beyond EOF')):
            case('roothide', name, command_word(good, 0x1d, field, value), 'Bad signature')
        case('roothide', 'duplicate signature commands',
             image('roothide', [version(), struct.pack('<4I', 0x1d, 16, 88, 12)]), 'Bad signature')

        strings = binary('roothide', deps=('/usr/lib/libSystem.B.dylib',), rpaths=('/usr/lib',))
        for cmd, label, minimum in ((0xc, 'dependency', 24), (0x8000001c, 'rpath', 12)):
            pos = command_position(strings, cmd)
            size = struct.unpack_from('<I', strings, pos + 4)[0]
            for offset in (minimum - 4, size):
                case('roothide', label + ' offset ' + str(offset), command_word(strings, cmd, 8, offset),
                     'Bad ' + label + ' offset')
            for mode in ('unterminated', 'empty', 'invalid utf8'):
                case('roothide', label + ' ' + mode, string_mutation(strings, cmd, mode),
                     'Bad ' + label + ' string')

    check(len(cases) >= 70, 'Empty or incomplete Mach-O fixture suite')
    print(json.dumps({'scope': 'direct validate.macho synthetic byte fixtures; signature command/range presence only; '
                              'NOT Apple build/full codesign/staging/setuid/device proof',
                      'checks': checks, 'cases': cases}, indent=2))


if __name__ == '__main__':
    main()
