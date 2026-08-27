# App Store listing

Everything App Store Connect asks for, kept here so it is version-controlled and
can be diffed against what the app actually does — rather than existing only in a
web form nobody can review.

**The text itself lives in `metadata/<locale>.json`**, English and the twenty
languages the app ships. This file is the reasoning behind it: why the name is
what it is, why the keywords leave out the obvious words, what Connect wants in
the fields that are not translated at all.

`python3 ../Tools/check_store_metadata.py` checks every locale against Apple's
limits — name and subtitle 30 characters, promotional text 170, keywords 100,
description and what's new 4000 — and against guideline 2.3.10, which disallows
naming another mobile platform anywhere in the metadata. Connect enforces the
limits one field at a time as you paste; the script does all twenty-one locales
at once.

Screenshots are in `../Screenshots/`, at every size Connect asks for:

    6.5-*.png     1284×2778   the 6.5" slot (iPhone 11/12/13/14 Pro Max, 14 Plus)
    6.9-*.png     1320×2868   the 6.9" slot (iPhone 16/17 Pro Max)
    ipad13-*.png  2064×2752   the 13" iPad slot — required, the app is universal

Which slots a listing shows varies, and Connect rejects anything that is not one
of its exact sizes rather than scaling it — so each is captured natively from a
simulator of the right model.

The iPad set is not optional: `TARGETED_DEVICE_FAMILY` is `1,2`, so the app is
offered on iPad and Connect will not accept the listing without it. Three shots
per size, one per tab.

---

## Name (30 max)

`name` — the same in every locale. "Weekly Budget" is taken; App Store names are globally unique, unlike Google
Play, where the Android app keeps that name. The home-screen name is separate and
stays "Weekly Budget" (`INFOPLIST_KEY_CFBundleDisplayName`), so on a phone with
both apps the icons match.

Nothing below names Android, on purpose. Guideline 2.3.10 disallows naming other
mobile platforms in an app *or its metadata*, and a first submission is a poor
place to test how strictly that is read — so the copy says "other phones" and the
in-app link goes to budget.andrewovens.com/Apps, which is free to be specific.

## Subtitle (30 max)

`subtitle`. Deliberately does not repeat "weekly" or "spend". Apple indexes the name,
subtitle and keywords as one pool, so a word spent twice is a word wasted — this
adds "budget" and "together" instead.

## Promotional text (170 max)

`promotionalText`. The tightest field after the subtitle: French lands at 167 of
the 170 characters, so a longer English line would not survive translation.

Promotional text can be changed any time without submitting a new build, so it is
the right place for anything seasonal or temporary.

## Description (4000 max)

`description`. Structured as: what it answers, what it deliberately does not do,
sharing, offline, a feature list, and the privacy paragraph. The section headings
are shouted in the English because the App Store has no formatting; each
translation shouts in whatever way that language does — the CJK locales use
bracketed headings instead of capitals, which do not exist there.

The wording matches the app's own copy where they overlap. Someone who reads the
listing and then opens the tutorial should not be told two different things.

## Keywords (100 max, comma separated, no spaces)

`keywords`. Not a translation: each locale gets the words people actually search
for in that language, and the words already indexed from that locale's name and
subtitle are left out of it.

Chosen to add terms the name and subtitle do not already cover. "weekly",
"spend", "budget" and "together" are omitted on purpose — they are indexed from
the name and subtitle, and repeating them here would waste the allowance.

## What's New (4000 max)

`whatsNew`, replaced for each release. The text currently in the files is for the
release that adds the twenty languages and the weekly-number helper.

## Categories

Primary: Finance
Secondary: Utilities

Finance is where anyone looking for this would search. Utilities rather than
Productivity for the secondary: the app is a single-purpose tool, not a system for
organising your life.

## URLs

Support URL:        https://budget.andrewovens.com
Marketing URL:      https://budget.andrewovens.com
Privacy policy URL: https://budget.andrewovens.com/privacy

## Copyright

2026 Andrew Ovens

## Age rating

4+ — no objectionable content, no user-generated content shown to other people,
no web browsing, no advertising, no gambling.

## App Privacy answers

Data Not Linked to You → Other User Content → App Functionality only. That covers
the expense descriptions and amounts. Not used for tracking.

Everything else: No. There is no identifier to link anything to, which is why
this section is unusually short for a finance app.

Note the server keeps aggregate daily request counts, which is described in the
privacy policy. It is not per-person and carries no identifier, so it is not
declarable data collection under Apple's definitions — but the policy states it
plainly rather than relying on that.

## Review notes

No account or login is required, so there are no test credentials to provide.
Launching the app offers "Create" or "Join"; choosing Create makes a working
budget immediately.

The app talks to budget.andrewovens.com, a server the developer also runs. A
budget is addressed by a random ID generated on the device. Anyone holding that ID
can read and change that budget — this is intentional, it is how sharing between
devices works, and it is stated plainly in the privacy policy.

Income is entered as an expense with a negative amount. This is deliberate and
explained in the app's own "How this works" screen, reachable from Settings.

For context, since these notes are not public: this app has existed on another
platform for several years and this is the same product on the same server, which
is why it arrives feature-complete rather than as a first draft. "Apps for other
devices" in Settings opens a page on the developer's own site, not a store.
