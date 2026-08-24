1. SCREEN RECORDING

Attached: 71 seconds from a cold launch on an iPhone 17 Pro simulator — intro
cards, joining the demo budget below, a $12.50 expense taking the week's balance
from $285.05 to $272.55, then Month, Categories, Settings and About. The flows you
ask about do not exist here, so none are shown:

- No accounts: no registration, no login, nothing to delete. A budget is created
  locally and identified by a random UUID generated on the device.
- No paid content: free, no purchases, no subscriptions, no StoreKit code.
- No content visible to other people. An expense is readable only on devices
  already holding that budget's ID, so there is nothing to report or block.
- No permission prompts: no location, contacts, camera, photos, microphone,
  notifications or App Tracking Transparency, and so no purpose strings. The only
  entitlement is Associated Domains, so an invitation link opens the app rather
  than Safari.

2. TESTED ON

iPhone 17 Pro simulator (iOS 26.5) and iPad Pro 13-inch M5 simulator (iPadOS
26.5) — not on physical hardware. Every change also runs 20 UI tests across both
device families and 100 unit assertions.

3. WHAT IT DOES, AND WHO FOR

You set one number — what you can spend in a week — and the app answers one
question: what is left of it. An expense is a description, an amount, a date and an
optional category. A month is too long to feel: spend most of it by the 10th and
you only find out when the money is gone.

It is for people who budget weekly rather than monthly, especially couples sharing
one pot: a budget lives on several devices and stays in step. It has existed on
another platform for years and is the same product on the same server, which is why
a first submission arrives feature-complete.

Two omissions are deliberate, in case they read as gaps. There is nowhere to enter
recurring bills, because fixed amounts bury the number that moves, and money
arriving mid-week is a negative expense, as the app's "How this works" explains.

4. SETUP AND ACCESS

No credentials: there are no accounts. For a populated app, launch it, choose
"Join with an ID" and enter

    72b1a062-bf95-48cb-bde1-bee2b528e200

which exists for review, holds no personal data and is safe to change.

On Week, "+" adds, tapping a row edits, swiping left deletes, long press copies
into next week, and chevrons or a sideways swipe change week. Month totals each
week; Categories charts them, and tapping a slice lists what is behind it. The gear
icon holds the budget's settings, "Create an invitation" (a one-time sharing link),
the budget ID, and About.

5. EXTERNAL SERVICES

One, the developer's own: budget.andrewovens.com, a Node.js and PostgreSQL server
on their own hardware. It stores only what is typed in — the budget's name, weekly
amount and start day, and each expense's description, amount, date and category —
and no personal information, because the app never asks for any.

Everything else is Apple's: SwiftUI, SwiftData, Swift Charts, Foundation. There are
no third-party dependencies at all: no analytics, crash reporting, advertising,
attribution, authentication, payment processing, AI or data provider.

The server keeps daily per-endpoint request counts to know it is working: counts,
not events, tied to no person or device, and described in the privacy policy.

6. REGIONAL DIFFERENCES

None. No region gating or geographic restriction, English only. Amounts follow the
device's currency and dates its locale. A budget "day" is handled in UTC, so an
expense falls on the same day on every device sharing a budget.

7. REGULATED INDUSTRY AND THIRD-PARTY MATERIAL

Neither applies. This is a note-keeping tool for money the user types in, not a
financial institution nor acting for one: no bank connections, no payment
processing, no card details, no credit or transaction data, no financial advice,
and nothing requiring a licence. It holds no protected third-party material; the
icon, artwork and copy are the developer's own.
