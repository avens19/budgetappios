#!/usr/bin/env python3
"""Check Store/metadata against App Store Connect's limits.

    python3 Tools/check_store_metadata.py

Connect rejects an over-long field when you save the page, one field at a time,
after a paste — which is a slow way to discover that the German subtitle is four
characters too long. This checks all of it at once, before anyone opens a
browser.

The limits are Apple's: name 30, subtitle 30, promotional text 170, keywords
100, description 4000, what's new 4000. Keywords are counted as Apple counts
them — the whole comma-separated string, spaces included, so a stray space after
a comma costs a character of search allowance.
"""

import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
METADATA = os.path.join(ROOT, 'Store', 'metadata')

LIMITS = {
    'name': 30,
    'subtitle': 30,
    'promotionalText': 170,
    'keywords': 100,
    'description': 4000,
    'whatsNew': 4000,
}

# App Store Connect's locale codes, which are not the ones the app's catalog
# uses: Connect wants es-MX for Latin American Spanish where the catalog says
# es-419, and ar-SA where the catalog says ar.
LOCALES = ['en-US', 'ar-SA', 'de-DE', 'es-ES', 'es-MX', 'fr-FR', 'hi', 'id', 'it',
           'ja', 'ko', 'nl-NL', 'pl', 'pt-BR', 'pt-PT', 'ru', 'tr', 'uk', 'vi',
           'zh-Hans', 'zh-Hant']


def main():
    found = {os.path.basename(p)[:-5] for p in glob.glob(os.path.join(METADATA, '*.json'))}

    problems = ['no metadata for %s' % locale for locale in sorted(set(LOCALES) - found)]
    problems += ['%s is not a locale this app ships' % locale
                 for locale in sorted(found - set(LOCALES))]

    english = json.load(open(os.path.join(METADATA, 'en-US.json'), encoding='utf-8'))

    for locale in sorted(found & set(LOCALES)):
        with open(os.path.join(METADATA, '%s.json' % locale), encoding='utf-8') as handle:
            fields = json.load(handle)

        for field, limit in LIMITS.items():
            value = fields.get(field)
            if not value:
                problems.append('%s: %s is empty' % (locale, field))
                continue
            if len(value) > limit:
                problems.append('%s: %s is %d characters, limit is %d'
                                % (locale, field, len(value), limit))

        # The app's name is globally unique on the App Store and is the thing
        # people are told to search for. It is not translated.
        if fields.get('name') != english['name']:
            problems.append('%s: name is %r, expected the untranslated %r'
                            % (locale, fields.get('name'), english['name']))

        # Keywords are a comma-separated list with no spaces: a space is a
        # character of the hundred, spent on nothing.
        keywords = fields.get('keywords', '')
        if ', ' in keywords:
            problems.append('%s: keywords contain ", " - Apple counts the space'
                            % locale)
        if keywords.strip(',') != keywords or ',,' in keywords:
            problems.append('%s: keywords have an empty entry' % locale)

        # Nothing may name another mobile platform: guideline 2.3.10 covers
        # metadata as well as the app.
        for banned in ('Android', 'Google Play', 'Play Store'):
            for field in ('subtitle', 'promotionalText', 'description', 'whatsNew'):
                if banned.lower() in fields.get(field, '').lower():
                    problems.append('%s: %s names %s, which 2.3.10 disallows'
                                    % (locale, field, banned))

    if problems:
        print('\n'.join(problems))
        print('\n%d problem(s)' % len(problems))
        return 1

    print('%d locales, every field present and inside Apple\'s limits' % len(found))
    for field in ('subtitle', 'promotionalText', 'keywords'):
        longest = max(
            (len(json.load(open(os.path.join(METADATA, '%s.json' % l), encoding='utf-8'))[field]), l)
            for l in sorted(found))
        print('  longest %-16s %s at %d (limit %d)'
              % (field, longest[1], longest[0], LIMITS[field]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
