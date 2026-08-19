# App Store listing

Everything App Store Connect asks for, kept here so it is version-controlled and
can be diffed against what the app actually does — rather than existing only in a
web form nobody can review.

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

Weekly Spend

"Weekly Budget" is taken; App Store names are globally unique, unlike Google
Play, where the Android app keeps that name. The home-screen name is separate and
stays "Weekly Budget" (`INFOPLIST_KEY_CFBundleDisplayName`), so on a phone with
both apps the icons match.

Nothing below names Android, on purpose. Guideline 2.3.10 disallows naming other
mobile platforms in an app *or its metadata*, and a first submission is a poor
place to test how strictly that is read — so the copy says "other phones" and the
in-app link goes to budget.andrewovens.com/Apps, which is free to be specific.

## Subtitle (30 max)

Budget by the week, together

Deliberately does not repeat "weekly" or "spend". Apple indexes the name,
subtitle and keywords as one pool, so a word spent twice is a word wasted — this
adds "budget" and "together" instead.

## Promotional text (170 max)

One number, kept honest: what is left to spend this week. Share a budget with a
partner and it stays in step across their phone and the web too — no account
needed.

Promotional text can be changed any time without submitting a new build, so it is
the right place for anything seasonal or temporary.

## Description (4000 max)

Weekly Spend answers one question: how much is left to spend this week?

Work out what you have after the bills that never change — rent, insurance,
subscriptions — split it across the weeks in the month, and that is your weekly
target. Add expenses as you go and watch the number come down. That is the whole
idea.

WHAT IT DELIBERATELY DOES NOT DO

There is nowhere to enter your salary, your rent, or any other recurring amount.
Those numbers are already decided, and putting them in an app does not change
them. Leaving them out is what keeps this on the one figure that actually moves
day to day. If money arrives mid-week — a refund, a gift, cash back — add it as
an expense with a minus sign.

No budgets to rebalance every month. No charts to interpret. No lectures.

SHARED, PROPERLY

One budget can live on as many devices as you like. Copy the budget ID, enter it
on your partner's phone, and you both see the same running total within seconds —
add a coffee on the way home and it is there before you are.

The same budget opens on other phones and at budget.andrewovens.com, so a
household running a mix of phones is not a problem, and neither is checking it
from a laptop.

WORKS WITHOUT A SIGNAL

Everything lives on the device and syncs when it can. Add an expense in a
basement car park and it is saved; it reaches the other devices when you surface.
Nothing is lost waiting for a connection.

WHAT YOU GET

• One clear number: what is left this week
• Expenses grouped by day, with a running total for each
• Categories, and a breakdown by week or month
• A month view showing every week against your target
• Carry an unspent balance forward into next week
• Copy a repeating expense to next week in one tap

NO ACCOUNTS, NO ADVERTISING, NO TRACKING

There is nothing to sign up for and no password to forget. No advertising, no
analytics SDKs, no third-party services of any kind. There is no name, email
address or phone number collected, because there is nowhere to enter one — a
budget is identified by a random ID that only you and the people you share it
with have.

Built and run by one person, not a company with an exit strategy.

## Keywords (100 max, comma separated, no spaces)

allowance,expenses,tracker,money,cash,couples,partner,shared,envelope,simple,pocket,paycheck

Chosen to add terms the name and subtitle do not already cover. "weekly",
"spend", "budget" and "together" are omitted on purpose — they are indexed from
the name and subtitle, and repeating them here would waste the allowance.

## What's New (4000 max)

First release.

This is the same budget and the same server that other versions of the app have
used for years — only now on iPhone and iPad. If you already use it elsewhere,
enter your budget ID in Settings and everything appears.

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
