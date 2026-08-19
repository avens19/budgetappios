# App Store listing

Copy for App Store Connect. Kept here so it is version-controlled and matches
what the app actually does, rather than living only in a web form.

Screenshots are in `../Screenshots/`, at both sizes Connect asks for:

    6.5-*.png   1284×2778   the 6.5" slot (iPhone 11/12/13/14 Pro Max, 14 Plus)
    6.9-*.png   1320×2868   the 6.9" slot (iPhone 16/17 Pro Max)

Which slots a listing shows varies, and Connect rejects anything that is not one
of its exact sizes rather than scaling it — so both are captured natively from a
simulator of the right model. Rescaling the 6.9" set would have meant either
padding or cropping, since the two aspect ratios are not identical.

## Name

Weekly Spend

"Weekly Budget" is taken on the App Store, where names are globally unique —
unlike Google Play, where the Android app keeps that name. "Weekly Spend" holds
onto the words someone looking for this would actually search for.

The home-screen name is separate and stays "Weekly Budget"
(INFOPLIST_KEY_CFBundleDisplayName), so the icon matches the Android app on a
phone that has both.

## Subtitle (30 characters max)

What's left to spend this week

## Promotional text (170 max)

One number, updated as you spend: what is left this week. Share a budget with a
partner and it stays in step across iPhone, Android and the web.

## Description

Weekly Spend answers one question: how much is left to spend this week?

Work out what you have after the bills that never change — rent, insurance,
subscriptions — split it across the weeks in the month, and that is your weekly
target. Add expenses as you go and watch the number come down.

That is deliberately all it does. There is nowhere to enter recurring income or
fixed expenses, because those amounts are already decided; leaving them out keeps
the app on the one number that actually moves. If money arrives mid-week — a
refund, a gift, cash back — add it as an expense with a minus sign.

SHARED, PROPERLY
One budget can live on as many devices as you like. Copy the budget ID, enter it
on your partner's phone, and you both see the same running total within seconds.
The same budget opens in the Android app and at budget.andrewovens.com, so a
household with a mix of phones is not a problem.

WORKS WITHOUT A SIGNAL
Everything is stored on the device and syncs when it can. Add an expense in a
basement car park and it is there; it reaches the other devices when you surface.

WHAT YOU GET
• One clear number: what is left this week
• Expenses grouped by day, with a running daily total
• Categories, with a breakdown by week or month
• A month view showing each week against your target
• Carry an unspent balance into next week
• No account, no email address, no password

NO ACCOUNTS, NO ADVERTISING
There is nothing to sign up for. No advertising, no trackers, no third-party
services, and nothing about you is collected — there is no name or email address
to collect. A budget is identified by a random ID that only you have.

## Keywords (100 characters max, comma separated)

budget,weekly,spending,expenses,money,allowance,shared,couples,cash,simple

## Support URL

https://budget.andrewovens.com

## Marketing URL

https://budget.andrewovens.com

## Privacy policy URL

https://budget.andrewovens.com/privacy

## Age rating

4+ — no objectionable content, no user-generated content shown to others, no web
browsing, no advertising.

## App Privacy answers

Data Not Linked to You → Other User Content, used for App Functionality only.
That covers the expense descriptions and amounts. Not used for tracking. There is
no identifier to link anything to, which is why this section is short.

Everything else: No.

## Review notes

No account is needed. Launching the app offers "Create" or "Join"; choosing
Create makes a working budget immediately, so there are no credentials to supply.

The app talks to budget.andrewovens.com, which the developer also runs. A budget
is addressed by a random ID generated on the device; anyone holding that ID can
read and change that budget, which is how sharing between devices works and is
stated plainly in the privacy policy.
