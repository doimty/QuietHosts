#!/usr/bin/env python3
"""Offline Localizable.strings and NSL literal coverage checks (no dependencies).

English source strings are keys. Runtime NSL(variable) calls are allowed; only
literal arguments can be checked statically. Use --source-root for fixtures and
--resources to validate staged resource bundles. Run --self-test for negatives.
"""
import argparse
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import re
import sys
import tempfile
import unittest


class ValidationError(ValueError):
    pass


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    line: int


def quoted(text, start, source=False):
    """Decode a quoted OpenStep/C string without eval or lossy Unicode codecs."""
    quote = text[start]
    i = start + 1
    result = []
    escapes = {'n': '\n', 'r': '\r', 't': '\t', 'b': '\b', 'f': '\f',
               'v': '\v', 'a': '\a', '"': '"', "'": "'", '\\': '\\', '?': '?'}
    while i < len(text):
        char = text[i]
        i += 1
        if char == quote:
            try:
                # OpenStep files can express non-BMP characters as UTF-16 pairs.
                value = ''.join(result).encode('utf-16-le', 'surrogatepass').decode('utf-16-le')
            except UnicodeError as error:
                raise ValidationError('invalid Unicode surrogate') from error
            return value, i
        if char == '\n' or char == '\r':
            raise ValidationError('unescaped newline in string')
        if char != '\\':
            result.append(char)
            continue
        if i >= len(text):
            raise ValidationError('unterminated escape')
        char = text[i]
        i += 1
        if char in escapes:
            result.append(escapes[char])
        elif char in ('U', 'u'):
            count = 8 if source and char == 'U' else 4
            digits = text[i:i + count]
            if (len(digits) != count or not re.fullmatch(r'[0-9A-Fa-f]+', digits)
                    or int(digits, 16) > 0x10ffff):
                raise ValidationError('invalid Unicode escape')
            result.append(chr(int(digits, 16)))
            i += count
        elif char == 'x' and source:
            match = re.match(r'[0-9A-Fa-f]+', text[i:])
            if not match or int(match.group(), 16) > 0x10ffff:
                raise ValidationError('invalid hexadecimal escape')
            result.append(chr(int(match.group(), 16)))
            i += len(match.group())
        elif char in '01234567':
            digits = char
            while i < len(text) and len(digits) < 3 and text[i] in '01234567':
                digits += text[i]
                i += 1
            result.append(chr(int(digits, 8)))
        elif char == '\n':
            pass  # C backslash-newline continuation.
        elif char == '\r' and i < len(text) and text[i] == '\n':
            i += 1
        else:
            raise ValidationError(f'unsupported escape: \\{char}')
    raise ValidationError('unterminated quoted string')


def tokens(text, source=False):
    result = []
    i, line = 0, 1
    while i < len(text):
        start = i
        if text[i].isspace() or text[i] == '\ufeff':
            i += 1
        elif text.startswith('//', i):
            end = text.find('\n', i)
            i = len(text) if end < 0 else end
        elif text.startswith('/*', i):
            end = text.find('*/', i + 2)
            if end < 0:
                raise ValidationError(f'line {line}: unterminated comment')
            i = end + 2
        elif text.startswith('@"', i) or text[i] in ('"', "'"):
            objc = text.startswith('@"', i)
            quote_start = i + int(objc)
            value, i = quoted(text, quote_start, source=source)
            kind = 'objc' if objc else ('string' if text[quote_start] == '"' else 'char')
            result.append(Token(kind, value, line))
        elif text[i].isalpha() or text[i] == '_':
            i += 1
            while i < len(text) and (text[i].isalnum() or text[i] == '_'):
                i += 1
            result.append(Token('identifier', text[start:i], line))
        else:
            result.append(Token('symbol', text[i], line))
            i += 1
        line += text[start:i].count('\n')
    return result


def parse_strings(text):
    stream = tokens(text)
    values = {}
    i = 0
    while i < len(stream):
        row = stream[i:i + 4]
        if (len(row) != 4 or row[0].kind != 'string'
                or row[1].kind != 'symbol' or row[1].value != '='
                or row[2].kind != 'string' or row[3].kind != 'symbol' or row[3].value != ';'):
            raise ValidationError(f'line {stream[i].line}: expected "key" = "value";')
        key, value = row[0].value, row[2].value
        if key in values:
            raise ValidationError(f'line {row[0].line}: duplicate key {key!r}')
        values[key] = value
        i += 4
    return values


def extract_literals(text):
    stream = tokens(text, source=True)
    found = []
    for i, token in enumerate(stream):
        if token.kind != 'identifier' or token.value != 'NSL':
            continue
        if i + 2 >= len(stream) or stream[i + 1].value != '(' or stream[i + 2].kind != 'objc':
            continue  # Function definitions and NSL(runtimeKey) are intentional.
        j, parts = i + 2, []
        while j < len(stream) and stream[j].kind in ('objc', 'string'):
            parts.append(stream[j].value)
            j += 1
        if j < len(stream) and stream[j].value == ')':
            found.append((''.join(parts), token.line))
    return found


FORMAT = re.compile(
    r'%(?:(?P<position>[1-9][0-9]*)\$)?[-+ #0\']*'
    r'(?P<width>\*(?:[1-9][0-9]*\$)?|[0-9]+)?'
    r'(?:\.(?P<precision>\*(?:[1-9][0-9]*\$)?|[0-9]*))?'
    r'(?P<length>hh|ll|h|l|q|L|z|t|j)?(?P<type>[@diuoxXfFeEgGaAcCsSpnDUO])')


def placeholders(text):
    """Argument position/type multiplicities, including indexed '*' arguments."""
    result = Counter()
    next_position = 1
    modes = set()

    def argument(position, kind):
        nonlocal next_position
        modes.add('indexed' if position else 'sequential')
        if position:
            index = int(position)
        else:
            index = next_position
            next_position += 1
        result[(index, kind)] += 1

    i = 0
    while i < len(text):
        if text[i] != '%':
            i += 1
            continue
        if text.startswith('%%', i):
            result[(0, 'literal-percent')] += 1
            i += 2
            continue
        match = FORMAT.match(text, i)
        if not match:
            raise ValidationError(f'invalid format placeholder near {text[i:i + 20]!r}')
        for field in ('width', 'precision'):
            width = match.group(field)
            if width and width.startswith('*'):
                argument(width[1:-1] if width.endswith('$') else None, 'd')
        argument(match.group('position'), (match.group('length') or '') + match.group('type'))
        i = match.end()
    if len(modes) > 1:
        raise ValidationError('mixed indexed and sequential format arguments')
    return result


def source_files(root):
    folders = [root / 'App', root / 'Shared']
    folders.extend(sorted(p for p in root.glob('Filter*') if p.is_dir()))
    extensions = {'.h', '.m', '.mm', '.c', '.cc', '.cpp'}
    return sorted({p for folder in folders if folder.is_dir()
                   for p in folder.rglob('*') if p.is_file() and p.suffix in extensions})


def validate(resources, root):
    errors, locales = [], {}
    files = sorted(resources.glob('*.lproj/Localizable.strings'))
    for path in files:
        try:
            locales[path.parent.stem] = parse_strings(path.read_text(encoding='utf-8'))
        except (OSError, UnicodeError, ValidationError) as error:
            errors.append(f'{path}: {error}')
    for required in ('en', 'zh-Hans'):
        if required not in locales:
            errors.append(f'missing or invalid required locale: {required}')
    english = locales.get('en', {})
    for locale, values in locales.items():
        missing, extra = english.keys() - values.keys(), values.keys() - english.keys()
        for key in sorted(missing):
            errors.append(f'{locale}: missing key {key!r}')
        for key in sorted(extra):
            errors.append(f'{locale}: extra key not present in en: {key!r}')
        for key, value in values.items():
            if locale == 'en' and key != value:
                errors.append(f'en: value must match English fallback key {key!r}')
            try:
                if placeholders(key) != placeholders(value):
                    errors.append(f'{locale}: placeholder mismatch for {key!r}')
            except ValidationError as error:
                errors.append(f'{locale}: {key!r}: {error}')
    calls = 0
    sources = source_files(root)
    for path in sources:
        try:
            literals = extract_literals(path.read_text(encoding='utf-8'))
            calls += len(literals)
            for key, line in literals:
                for locale in ('en', 'zh-Hans'):
                    if key not in locales.get(locale, {}):
                        errors.append(f'{path}:{line}: NSL key missing from {locale}: {key!r}')
        except (OSError, UnicodeError, ValidationError) as error:
            errors.append(f'{path}: {error}')
    return errors, len(english), calls, len(sources)


class LocalizationTests(unittest.TestCase):
    def test_comments_and_escapes(self):
        text = '/* note */ "A\\n\\\"" = "中\\n\\\""; // note\n "url" = "https://a/*b*/";'
        self.assertEqual(parse_strings(text), {'A\n"': '中\n"', 'url': 'https://a/*b*/'})

    def test_unicode_and_octal(self):
        self.assertEqual(parse_strings(r'"\U4F60\U597D" = "\141\t\UD83D\UDE00";'),
                         {'你好': 'a\t😀'})

    def test_source_hex_and_unicode(self):
        self.assertEqual(extract_literals(r'const char *x = "\x01"; NSL(@"\U00004F60\u597D");'),
                         [('你好', 1)])
        with self.assertRaises(ValidationError):
            parse_strings(r'"x" = "\x41";')

    def test_quoted_separators_rejected(self):
        with self.assertRaises(ValidationError):
            parse_strings('"key" "=" "value" ";"')

    def test_duplicate(self):
        with self.assertRaisesRegex(ValidationError, 'duplicate'):
            parse_strings('"A" = "a"; "\\U0041" = "b";')

    def test_invalid_syntax(self):
        for text in ('"a"="b"', '"a"="b"; junk', '/*', '"a" = "\\k";', '"a\n"="b";'):
            with self.subTest(text=text), self.assertRaises(ValidationError):
                parse_strings(text)

    def test_multiline_concatenation(self):
        self.assertEqual(extract_literals('NSL(@"Hello "\n /* join */ @"world\\n")'),
                         [('Hello world\n', 1)])

    def test_c_string_concatenation(self):
        self.assertEqual(extract_literals('NSL(@"One" " two")'), [('One two', 1)])

    def test_ignore_comments_runtime_macros_and_raw_values(self):
        text = ('// NSL(@"Fake")\n/* NSL(@"No") */\n'
                '#define NSL(key) Lookup(key)\n'
                '#define NSAllowAction @"NETSHIELD_ALLOW"\n'
                'NSString *s = @"NSL(@\\"Nope\\")"; NSL(title); '
                '@{ @"action": @"allow" }; MyNSL(@"Other"); NSL(@"Yes");')
        self.assertEqual(extract_literals(text), [('Yes', 5)])

    def test_indexed_reordering(self):
        self.assertEqual(placeholders('%@ has %lu rules'), placeholders('%2$lu 条：%1$@'))

    def test_star_width_precision(self):
        self.assertEqual(placeholders('%*.*f'), placeholders('%3$*1$.*2$f'))

    def test_placeholder_mismatch(self):
        for original, mutated in (('%lu', '%u'), ('%@ %d', '%d %@'), ('%@', '%s'),
                                  ('%.1f', '%ld'), ('%@ %@', '%1$@ %1$@'), ('%%', '')):
            with self.subTest(original=original, mutated=mutated):
                self.assertNotEqual(placeholders(original), placeholders(mutated))

    def test_percent_escape(self):
        self.assertEqual(placeholders('100%%: %d'), Counter({(0, 'literal-percent'): 1, (1, 'd'): 1}))

    def test_bad_placeholders(self):
        for text in ('%1$@ %@', '%', '%Q', '%0$@'):
            with self.subTest(text=text), self.assertRaises(ValidationError):
                placeholders(text)

    def fixture(self, chinese='"Count %lu" = "数量 %lu";', source='NSL(@"Count %lu");'):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        resources = root / 'resources'
        for locale, text in [('en', '"Count %lu" = "Count %lu";'), ('zh-Hans', chinese)]:
            folder = resources / (locale + '.lproj')
            folder.mkdir(parents=True)
            (folder / 'Localizable.strings').write_text(text, encoding='utf-8')
        folder = root / 'App' / 'Nested'
        folder.mkdir(parents=True)
        (folder / 'NewUI.m').write_text(source, encoding='utf-8')
        return resources, root

    def test_valid_fixture(self):
        self.assertEqual(validate(*self.fixture())[0], [])

    def test_mutated_translation(self):
        errors = validate(*self.fixture('"Count %lu" = "数量 %u";'))[0]
        self.assertTrue(any('placeholder mismatch' in error for error in errors))

    def test_missing_translation_and_extra_key(self):
        errors = validate(*self.fixture('"Other" = "其他";'))[0]
        self.assertTrue(any('missing key' in error for error in errors))
        self.assertTrue(any('extra key' in error for error in errors))

    def test_new_source_missing_key(self):
        errors = validate(*self.fixture(source='NSL(@"New "\n @"screen");'))[0]
        self.assertTrue(any('New screen' in error and 'missing' in error for error in errors))

    def test_dynamic_extension_discovery(self):
        resources, root = self.fixture()
        folder = root / 'FilterFuture' / 'Nested'
        folder.mkdir(parents=True)
        (folder / 'Future.mm').write_text('NSL(@"Future");', encoding='utf-8')
        errors = validate(resources, root)[0]
        self.assertTrue(any('Future.mm' in error and 'missing' in error for error in errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    default_root = Path(__file__).resolve().parents[1]
    parser.add_argument('--source-root', type=Path, default=default_root)
    parser.add_argument('--resources', type=Path, help='default: <source-root>/Shared/Resources')
    parser.add_argument('--self-test', action='store_true', help='run offline positive and negative fixtures')
    args = parser.parse_args()
    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(LocalizationTests)
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    resources = args.resources or args.source_root / 'Shared' / 'Resources'
    errors, keys, calls, sources = validate(resources, args.source_root)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        print(f'Localization FAILED: {len(errors)} error(s).', file=sys.stderr)
        return 1
    print(f'Localization OK: {keys} English keys, locale parity and placeholders verified; '
          f'{calls} literal NSL calls across {sources} source files.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
