#!/usr/bin/env python3
"""Check Localizable.xcstrings against the strings the app actually asks for.

    python3 Tools/check_localizations.py

Xcode builds a String Catalog by scanning the source, and it will tell you about
a key with no translation — but only on a Mac, with the project open, and only
for the languages already in knownRegions. This does the same walk from the
command line, so a string added on any machine can be checked before it ships
half translated.

It reports three things:

  * a string the source asks for that the catalog does not have;
  * a language missing from a key the rest of them have;
  * a translation whose format specifiers do not match the key's, which is the
    failure that reaches a user as a sentence with the number missing.

It is deliberately a text scan rather than a Swift parse. That means it can be
fooled by an unusual construction, so a *new* kind of call site may need a
pattern adding here — the alternative was a dependency on a Swift toolchain,
which is the thing this script exists to work without.
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, 'WeeklyBudget', 'Localizable.xcstrings')
BACKSLASH = chr(92)

# The languages the app ships. Kept here rather than read from the catalog: the
# point is to notice when one of them is missing from it.
LANGUAGES = ['ar', 'de', 'es', 'es-419', 'fr', 'hi', 'id', 'it', 'ja', 'ko', 'nl',
             'pl', 'pt-BR', 'pt-PT', 'ru', 'tr', 'uk', 'vi', 'zh-Hans', 'zh-Hant']

# Places SwiftUI localises a literal, plus the two explicit forms.
PATTERNS = [
    r'Text\(\s*"((?:[^"\\]|\\.)*)"\s*\)',
    r'Button\(\s*"((?:[^"\\]|\\.)*)"',
    r'Label\(\s*"((?:[^"\\]|\\.)*)"',
    r'navigationTitle\(\s*"((?:[^"\\]|\\.)*)"',
    r'Section\(\s*"((?:[^"\\]|\\.)*)"',
    r'Picker\(\s*"((?:[^"\\]|\\.)*)"',
    r'TextField\(\s*"((?:[^"\\]|\\.)*)"',
    r'Toggle\(\s*"((?:[^"\\]|\\.)*)"',
    r'confirmationDialog\(\s*"((?:[^"\\]|\\.)*)"',
    r'\.alert\(\s*"((?:[^"\\]|\\.)*)"',
    r'String\(localized:\s*"((?:[^"\\]|\\.)*)"\s*\)',
    r'LocalizedStringKey\(\s*"((?:[^"\\]|\\.)*)"\s*\)',
    r'title:\s*"((?:[^"\\]|\\.)*)"',
    r'message:\s*"((?:[^"\\]|\\.)*)"',
    r'body:\s*"((?:[^"\\]|\\.)*)"',
]

SKIP_EXACT = {'0.00', '0', '—'}
# A label with no words in it: a date range is data, and it is built as a plain
# String anyway.
SKIP_KEYS = {'%@ – %@'}


def unescape(text):
    """Swift escapes become real characters: a catalog is keyed by the value."""
    return (text.replace(BACKSLASH + 'n', '\n')
                .replace(BACKSLASH + '"', '"')
                .replace(BACKSLASH + BACKSLASH, BACKSLASH))


def specifier(text):
    """Interpolation becomes the specifier Xcode would have generated."""
    out, i = [], 0
    while i < len(text):
        if text.startswith(BACKSLASH + '(', i):
            depth, j = 1, i + 2
            while j < len(text) and depth:
                if text[j] == '(':
                    depth += 1
                elif text[j] == ')':
                    depth -= 1
                j += 1
            inner = text[i + 2:j - 1]
            out.append('%lld' if re.match(r'Int\(|left\b|count\b', inner) else '%@')
            i = j
        else:
            out.append(text[i])
            i += 1
    return ''.join(out)


def wanted():
    """Every key the source asks the catalog for."""
    keys = set()

    def add(text):
        if not text or text in SKIP_EXACT:
            return
        if re.fullmatch(r'[a-z0-9.]+', text):      # an SF Symbol name
            return
        key = specifier(unescape(text))
        if key not in SKIP_KEYS:
            keys.add(key)

    for path in glob.glob(os.path.join(ROOT, 'WeeklyBudget', '**', '*.swift'), recursive=True):
        with open(path, encoding='utf-8') as handle:
            source = handle.read()
        for pattern in PATTERNS:
            for match in re.finditer(pattern, source, re.S):
                add(match.group(1))
        for block in re.finditer(r'body:\s*\[(.*?)\]\)', source, re.S):
            for text in re.findall(r'"((?:[^"\\]|\\.)*)"', block.group(1)):
                add(text)
        for block in re.finditer(r'\["Sunday".*?"Saturday"\]', source, re.S):
            for text in re.findall(r'"([A-Za-z]+)"', block.group(0)):
                add(text)
        for pair in re.findall(r'case \w+ = "(\w+)", \w+ = "(\w+)"', source):
            add(pair[0])
            add(pair[1])

    # The helper's prompts live in Core as plain text and are looked up as keys
    # by the view. Comments are skipped: they quote phrases too.
    core = os.path.join(ROOT, 'Core', 'Sources', 'BudgetCore', 'WeeklyNumber.swift')
    with open(core, encoding='utf-8') as handle:
        code = ''.join(line for line in handle
                       if not line.lstrip().startswith(('///', '//', '*')))
    for text in re.findall(r'"((?:[^"\\]|\\.)*)"', code):
        if len(text) > 2 and not re.fullmatch(r'[a-z]+', text):
            add(text)

    return keys


def placeholders(text):
    """The kinds of argument a string takes, position ignored.

    A translation is allowed - and for more than one argument, expected - to
    write %1$@ where the key writes %@: that is how a language that puts the
    number somewhere else says which argument it means. What has to match is
    how many arguments there are and what type each is.
    """
    return sorted(re.sub(r'^%\d+\$', '%', found)
                  for found in re.findall(r'%(?:\d+\$)?(?:@|lld)', text))


def main():
    with open(CATALOG, encoding='utf-8') as handle:
        catalog = json.load(handle)
    strings = catalog['strings']

    problems = []

    for key in sorted(wanted()):
        if key not in strings:
            problems.append('not in the catalog: %r' % key)
            continue

        localizations = strings[key].get('localizations', {})
        missing = [lang for lang in LANGUAGES if lang not in localizations]
        if missing:
            problems.append('%r is missing %s' % (key, ', '.join(missing)))

        for lang, unit in localizations.items():
            value = unit['stringUnit']['value']
            if placeholders(value) != placeholders(key):
                problems.append('%s %r: placeholders %s do not match %s'
                                % (lang, key, placeholders(value), placeholders(key)))

    stale = sorted(set(strings) - wanted())
    for key in stale:
        problems.append('in the catalog but nothing asks for it: %r' % key)

    if problems:
        print('\n'.join(problems))
        print('\n%d problem(s)' % len(problems))
        return 1

    print('%d strings, %d languages, all present and consistent'
          % (len(strings), len(LANGUAGES)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
