# App Review Information — Notes

Paste the block below into **App Store Connect → App Review Information → Notes**
for this and every future submission. It answers the seven questions asked in the
Guideline 2.1 "Information Needed" message, in the order they were asked, so a
reviewer can check them off without hunting.

Keep it in the repo and keep it current: the rejection said to include this
"for future submissions", so drifting from the truth here costs a review cycle.

---

## 1. Screen recording

`review-walkthrough.mp4` in this directory — 71 seconds, attach it to the reply.
**It was captured on a simulator, not a physical device**, which is not what was
asked for; see the warning under question 2. Recapture it on a real device if one
can be found:

    xcrun simctl io booted recordVideo walkthrough.mp4 &
    xcodebuild test ... -only-testing:WeeklyBudgetUITests/ReviewWalkthrough

It begins with a cold launch from the home screen. It pages through the intro cards, joins the
demo budget below, adds a £12.50 expense and holds on the remaining balance
dropping from $285.05 to $272.55, then shows Month, Categories, Settings and
About.

The app has none of the specific flows the request asks about, and the recording
therefore shows none of them:

- **No accounts.** There is no registration, no login, no sign-in of any kind, and
  so nothing to delete. A budget is created locally and identified by a random
  UUID generated on the device.
- **No paid content, purchases or subscriptions.** The app is free and contains no
  in-app purchases, no subscriptions and no paywall. There is no StoreKit code in
  the binary.
- **No user-generated content shown to other people.** Expense descriptions are
  typed by the person using the app and are visible only on devices that already
  hold that budget's ID. Nothing is published, shared publicly, or discoverable by
  other users, so there is no feed to report or block within.
- **No permission prompts at all.** The app requests no location, contacts,
  camera, photos, microphone, notifications, or App Tracking Transparency. It has
  no purpose strings because it asks for nothing. The only capability in its
  entitlements is Associated Domains, used so that an invitation link opens the
  app instead of Safari.

## 2. Devices and operating systems tested on

**Fill this in truthfully before replying, and read the warning below.**

Tested so far:

- iPhone 17 Pro simulator — iOS 26.5
- iPad Pro 13-inch (M5) simulator — iPadOS 26.5

Automated coverage runs on every change: 20 XCUITest interaction and accessibility
tests across both device families, and 100 assertions over the sync engine,
calendar and wire format.

> **Warning.** As of writing, the app has never been run on physical hardware —
> the developer does not own an iPhone. Two of Apple's seven questions assume
> otherwise: question 1 asks for a recording "captured on a physical device", and
> this question asks which devices it was tested on. Answering "simulators only"
> is honest and invites the 2.1 *Bugs and crashes* follow-up quoted at the foot of
> the rejection, which says plainly that apps are reviewed on physical devices and
> to test on each supported platform before submitting.
>
> The fix is one device for ten minutes: install the build through TestFlight on
> any real iPhone, use it briefly, record the walkthrough there, and replace both
> this list and the attached recording. Do that before replying if it is at all
> possible.

## 3. What the app does, and who it is for

**The problem.** Monthly budgets fail because a month is too long to feel. Someone
who has spent most of their discretionary money by the 10th has no way to know it
until the month ends and the money is gone.

**What it does.** You set one number — what you can spend in a week — and the app
answers one question: what is left of it. The week's remaining balance is the
largest thing on the screen. Expenses are a description, an amount, a date and an
optional category. That is the whole model.

**Who it is for.** People who budget their everyday spending weekly rather than
monthly, and particularly couples or housemates sharing one pot of spending money.
A budget can live on several devices at once and stays in step across them, which
is the feature the app exists for.

**Deliberate omissions, in case they read as gaps.** There is nowhere to enter
recurring bills or income, because those amounts are already fixed and including
them would bury the one number that moves. Money arriving mid-week is entered as
an expense with a negative amount; this is explained on the app's own "How this
works" screen, reachable from Settings.

## 4. Setting up and accessing every feature

**No credentials are needed, because there are no accounts.**

The fastest way to see a populated app is to join the demo budget:

1. Launch the app. The first screen offers **Create a budget** or **Join with an ID**.
2. Choose **Join with an ID** and enter:

       72b1a062-bf95-48cb-bde1-bee2b528e200

3. The Week tab fills with a week of expenses and four categories. Month and
   Categories are populated too.

This budget exists for review and is safe to change; nothing in it is personal
data. Creating a fresh budget instead also works in a few seconds — name it, give
it a weekly amount, and pick which weekday the week starts on.

Where each feature lives:

- **Week** — the running week. Tap **+** to add an expense; tap a row to edit;
  swipe a row left to delete; long-press a row to copy it into next week. The
  chevrons or a sideways swipe move between weeks. **Carry balance** moves an
  underspend into next week.
- **Month** — the same expenses totalled per week.
- **Categories** — a donut chart by category for the week or the month; tap a
  slice to see the expenses behind it. **Manage** renames and removes categories.
- **Settings** (the gear icon) — the budget's name, weekly amount and start day;
  **Create an invitation**, which produces a one-time link for sharing the budget;
  the budget ID; **Compact layout**; **How this works**; **About**; and
  **Remove from this device**.

## 5. External services, tools and platforms

**One, and it belongs to the developer.**

- **budget.andrewovens.com** — the sync server, written and operated by the
  developer on hardware they own. Node.js and PostgreSQL. It stores only what is
  typed into the app: budget name, weekly amount, start day, and each expense's
  description, amount, date and category. It holds no personal information because
  the app never asks for any.

Everything else is Apple's: SwiftUI, SwiftData, Swift Charts and Foundation.

There are **no third-party dependencies of any kind**. No analytics or crash
reporting SDK, no advertising, no attribution, no authentication provider, no
payment processor, no AI or machine-learning service, no data provider. The only
Swift package the project references is a local one inside this repository, which
holds the sync logic shared with the developer's other clients.

The server keeps daily request counts — how many requests, to which endpoint, from
which client, how many failed — to know whether it is working. They are counts per
day, not events, are not tied to a person or a device, and are described in the
privacy policy. No third party receives them.

## 6. Regional differences

**None. The app behaves identically everywhere.**

There is no region gating, no geographic restriction, and no content that varies
by country. The app is available in English only.

Two behaviours follow the device's own settings rather than a region of ours:
amounts are formatted in the currency the device is set to, and dates are
formatted in the device's locale. A budget "day" is a calendar day handled in UTC
so that the same expense falls on the same day on every device sharing a budget,
regardless of the time zones they are in.

## 7. Regulated industry and third-party material

**Neither applies.**

The app is a personal note-keeping tool for money the user types in themselves. It
is **not** a financial institution or a service acting for one. It does not connect
to any bank or financial account, does not process payments or transfers, does not
handle card details, does not access credit or transaction data, and offers no
financial, investment or tax advice. Nothing in it requires a licence or a
registration.

It contains no protected third-party material. The app icon, artwork and all copy
are the developer's own. It uses no licensed data, trademarks or content belonging
to anyone else.

---

## Also worth stating in the reply

The app has existed on another platform for several years and this is the same
product on the same server, which is why a first submission arrives
feature-complete rather than as a first draft.

"Apps for other devices" in Settings, and "Learn more" on the About screen, open
pages on the developer's own website — not a store, and not a purchase flow.
