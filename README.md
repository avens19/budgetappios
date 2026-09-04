# Weekly Budget for iOS

A native iPhone client for [Weekly Budget](https://budget.andrewovens.com),
sharing budgets with the [Android app](https://play.google.com/store/apps/details?id=com.andrewovens.weeklybudget2)
and the web app. Same budget id, same expenses, same running total.

SwiftUI and SwiftData, iOS 17 and later. No third-party dependencies.

    Core/                 BudgetCore — wire types, sync engine, calendar, palette
    WeeklyBudget/         the app: SwiftData models and SwiftUI views
    WeeklyBudget.xcodeproj

## Running it

Open `WeeklyBudget.xcodeproj` and run. The local Swift package in `Core` is
picked up automatically, and the source folders are file-system synchronized,
so adding a file to `WeeklyBudget/` is all it takes to include it in the target.

It talks to production by default. Point it somewhere else by constructing
`BudgetSession(container:api:)` with a `LiveAPIClient(baseURL:)`.

## Why the logic lives in a separate package

`Core` has no SwiftUI and no SwiftData in it, which means it builds and runs
from the command line, on a machine with no simulator and no Xcode:

    cd Core
    swift run BudgetCoreTests          # unit suite, no network
    swift run BudgetCoreLive           # against production, writes and cleans up
    swift run BudgetCoreLive http://localhost:3111

That matters because the sync engine is the part that can quietly lose
somebody's money, and it is the part that has to agree exactly with two other
clients. Being able to test it without the simulator in the loop is worth the
extra target.

`BudgetCoreLive` creates a throwaway budget, exercises every endpoint, runs an
offline-then-sync round trip, and deletes the budget again.

## Languages

English is the source language; twenty more ship in
`WeeklyBudget/Localizable.xcstrings`, the same set as the Android app and the
website: ar, de, es, es-419, fr, hi, id, it, ja, ko, nl, pl, pt-BR, pt-PT, ru,
tr, uk, vi, zh-Hans, zh-Hant.

Most of those translations came from the other two clients rather than being
written again. The copy is deliberately word for word across the three, so a
sentence already translated for Android or the web is the same sentence here.

Two things to know before adding a string:

**`Text(someString)` does not localise.** It renders the string. Only a literal,
a `LocalizedStringKey`, or `String(localized:)` reaches the catalog — which is
why `EmptyState`, `PeriodPickerSheet` and the tutorial's page models take
`LocalizedStringKey`, and why the error messages are built with
`String(localized:)`. The helper's prompts live in `Core` as plain `String`, so
`WeeklyNumberView` wraps each one in `LocalizedStringKey`; `Core` stays free of
SwiftUI, which is the point of it.

**Check it without Xcode.** `python3 Tools/check_localizations.py` walks the
source for every string the app asks for and reports anything the catalog is
missing, any language missing from a key, and any translation whose format
specifiers do not match. Xcode does the equivalent on a Mac with the project
open; this runs anywhere, which is where the strings usually get added.

## The bits that are not obvious

**Everything is UTC.** A budget date is a calendar day, not an instant. It is
parsed, stored and rendered in UTC so that it cannot shift when the phone
changes timezone — an expense on the 14th is on the 14th in Auckland and in
Los Angeles. `BudgetCalendar.today()` is the one exception: it reads the
device's *local* day and reinterprets it as UTC, because "today" means the
user's today.

**The watermark is the server's clock, never the phone's.** The change feed
returns everything with `DateUpdated > watermark` and stamps the response with
`X-Watermark`. Storing a locally generated timestamp instead is silent data
loss — a phone running a minute fast never sees what another device wrote
inside that minute. This was a real bug in the Android client. When the two
feeds return different watermarks the *earlier* one is stored, and when either
is missing the stored one is left alone.

**Local ids start at 10<sup>12</sup>.** A row created offline needs an id
immediately and must not collide with the server's bigserial, currently in the
millions. Android uses the same base, which matters when both phones are
offline against the same budget.

**Category colour is rank in id order,** not a hash of the id. The same rule is
in `CategoryIndex` on Android and `categoryIndex()` on the web, so a category is
the same colour everywhere. Hashing collides too often at ten colours to be
worth it.

**Carried balance is a negative system expense** dated to the next week's first
day. It is excluded from the category chart, along with every other `IsSystem`
row and every category whose total is not positive — which is exactly what the
Android query does.

## Protocol

`CONTRACT.md` in the server repo is the authority. The parts that bite:

- PascalCase keys, case-insensitive routes.
- `PUT` returns **204 with an empty body**. Do not try to decode it.
- `GET /api/budget/{id}` returns **404** for an unknown id, and that is a normal
  answer — it is how joining a mistyped id fails.
- `X-Watermark` is fixed-width (28 characters). Watermarks are compared as
  strings, which is only sound while the width never varies.
- Deletes are soft on the server, so the feed can carry the deletion to other
  devices.

## Not here yet

- The home-screen widget the Android app has.
- App Store metadata and screenshots; the bundle id is
  `com.andrewovens.weeklybudget` and signing is left unset.
