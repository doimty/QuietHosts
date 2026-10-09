"""Project guarded platform additions back to the existing RootHide freeze."""
GUARD = '#if defined(QH_ROOTLESS) && QH_ROOTLESS\n'

def _project_c(s):
    lines = s.splitlines(keepends=True)
    out = []
    i = 0
    while i < len(lines):
        if lines[i] != GUARD:
            out.append(lines[i]); i += 1; continue
        depth = 1
        j = i + 1
        alternate = None
        while j < len(lines):
            line = lines[j].strip()
            if line.startswith(('#if ', '#if(', '#ifdef ', '#ifndef ')):
                depth += 1
            elif line == '#endif':
                depth -= 1
                if not depth:
                    break
            elif line == '#else' and depth == 1:
                assert alternate is None
                alternate = j + 1
            j += 1
        assert depth == 0, 'Unclosed platform guard'
        if alternate is not None:
            out.append(_project_c(''.join(lines[alternate:j])))
        i = j + 1
    return ''.join(out)

def project_frozen_text(s, path):
    if path == 'layout/DEBIAN/prerm':
        new = "  printf '%s\\n' '{}' | /usr/libexec/quiethosts-helper restore-for-uninstall || {\n"
        old = "  /usr/libexec/quiethosts-helper restore-for-uninstall </dev/null || {\n"
        assert s.count(new) == 1, 'Expected exactly one checked pipe input'
        s = s.replace(new, old, 1)
    if path == 'Helper/QHDirectoryPolicy.h':
        begin = '/* QH_ROOTHIDE_ROOTFS_ALIAS_BEGIN\n'
        end = '/* QH_ROOTHIDE_ROOTFS_ALIAS_END */'
        assert s.count(begin) == 1 and s.count(end) == 1, 'RootHide alias extension markers must stay unique'
        start = s.index(begin)
        finish = s.index(end, start) + len(end)
        assert s.startswith('\n\n#endif\n', finish), 'Alias block closing layout changed'
        finish += 2
        assert finish > start
        s = s[:start] + s[finish:]
    if path == 'Helper/QHFileManager.m':
        for label in ('CAPTURE', 'RECHECK'):
            begin = f'/* QH_PAIR_TARGET_{label}_BEGIN */\n'
            end = f'/* QH_PAIR_TARGET_{label}_END */\n'
            assert s.count(begin) == 1 and s.count(end) == 1, 'Pair target markers must stay unique'
            start = s.index(begin)
            finish = s.index(end, start) + len(end)
            s = s[:start] + s[finish:]
    if path == 'Makefile':
        s = s.replace('scripts/validate.py --stage "$(THEOS_STAGING_DIR)" --scheme "$(QH_SCHEME)"',
                      'scripts/validate.py --stage "$(THEOS_STAGING_DIR)"')
        s = s.replace(
            '# Explicit package environment; never use rootless compatibility shims.\n'
            'export QH_SCHEME ?= roothide\nifeq ($(QH_SCHEME),roothide)\n'
            'THEOS_PACKAGE_SCHEME = roothide\nexport ARCHS = arm64e\n'
            'else ifeq ($(QH_SCHEME),rootless)\nTHEOS_PACKAGE_SCHEME = rootless\n'
            'export ARCHS = arm64\nTHEOS_LAYOUT_DIR_NAME = layout-rootless\n'
            'else\n$(error Unsupported QH_SCHEME: $(QH_SCHEME))\nendif\n'
            'export TARGET = iphone:clang:16.5:15.0',
            '# Native roothide candidate; do not package rootless compatibility shims.\n'
            'THEOS_PACKAGE_SCHEME = roothide\nexport TARGET = iphone:clang:16.5:15.0\n'
            'export ARCHS = arm64e')
    if path in ('Helper/main.m', 'Helper/QHFileManager.m', 'Shared/QHBridge.m'):
        s = _project_c(s)
    if path in ('Helper/main.m', 'Shared/QHBridge.m'):
        s = s.replace('#import "../Shared/QHPlatform.h"', '#import <roothide.h>')
        s = s.replace('#import "QHPlatform.h"', '#import <roothide.h>')
        s = s.replace('QH_PLATFORM_PATH(', 'jbroot(')
    if path in ('App/Makefile', 'Helper/Makefile'):
        start = '# QH_ROOTLESS_BUILD_BEGIN\n'
        end = '# QH_ROOTLESS_BUILD_END\n'
        assert s.count(start) == 1 and s.count(end) == 1
        a, b = s.index(start), s.index(end) + len(end)
        s = s[:a] + s[b:]
    return s
