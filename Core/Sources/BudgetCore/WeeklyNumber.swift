import Foundation

/// The arithmetic behind "what should my weekly number be", and the prompts
/// that make it up.
///
/// The app asks for one figure and, outside the tutorial's first page, never
/// says where it comes from. Someone who has not done this sum before either
/// opens a spreadsheet or guesses, and a guessed number is how a budget ends up
/// impossible or meaningless.
///
/// Everything is annualised before it is compared. Amounts arrive on wildly
/// different cycles — pay every two weeks, rent monthly, insurance yearly — and
/// the usual shortcut of calling a month "four weeks" loses four weeks a year,
/// about 8% of the budget, which is the difference between a number that works
/// and one that quietly runs out every autumn.
///
/// It lives in Core, with no SwiftUI in it, so the sum can be tested from the
/// command line — and so the three clients can be checked against each other:
/// the same prompts in the same order mean a number worked out on the phone is
/// reproducible on the website.
public enum WeeklyNumber {

    public static let weeksPerYear = 52.0
    public static let monthsPerYear = 12.0

    /// How often an amount arrives, and what that comes to in a year.
    public enum Period: String, CaseIterable, Sendable {
        case weekly, fortnightly, semiMonthly, monthly, yearly

        public var perYear: Double {
            switch self {
            case .weekly: 52
            case .fortnightly: 26
            case .semiMonthly: 24
            case .monthly: 12
            case .yearly: 1
            }
        }

        /// The key the UI localises. Kept here so the order of the picker and
        /// the order of the cases cannot drift apart.
        public var label: String {
            switch self {
            case .weekly: "Weekly"
            case .fortnightly: "Every 2 weeks"
            case .semiMonthly: "Twice a month"
            case .monthly: "Monthly"
            case .yearly: "Yearly"
            }
        }
    }

    /// Which side of the sum a prompt sits on, and the heading it appears under.
    public enum Group: String, CaseIterable, Sendable {
        case income, fixed, steady

        public var title: String {
            switch self {
            case .income: "Money coming in"
            case .fixed: "Bills that don't change"
            case .steady: "Steady spending (optional)"
            }
        }

        public var help: String {
            switch self {
            case .income:
                "What actually lands in the account, after tax and deductions."
            case .fixed:
                "The amounts that go out whether you think about them or not. Savings belongs here too: money you have decided not to spend is not spending money."
            case .steady:
                "Things that vary a little but never surprise you. Subtract them here and they stay out of the app; leave them blank and enter them week to week instead. One or the other, not both."
            }
        }
    }

    /// One prompt: what it is called, where it sits, and the cycle it starts on.
    ///
    /// The list is prompts rather than a taxonomy. Someone who has never written
    /// this sum down does not know what to include, and a blank pair of "income"
    /// and "expenses" boxes gets an answer that forgets the car insurance; a
    /// named row is a reminder, and one left empty costs nothing.
    public struct Line: Identifiable, Sendable {
        public let id: Int
        public let label: String
        public let group: Group
        public let period: Period
    }

    /// The prompts, in the order they are asked — the same seventeen, in the
    /// same order, as the Android app and the website.
    public static let lines: [Line] = {
        let specs: [(String, Group, Period)] = [
            ("Take-home pay", .income, .fortnightly),
            ("Other income", .income, .monthly),

            ("Rent or mortgage", .fixed, .monthly),
            ("Power, heat, water", .fixed, .monthly),
            ("Phone and internet", .fixed, .monthly),
            ("Insurance", .fixed, .monthly),
            ("Car payment or transit pass", .fixed, .monthly),
            ("Loan and credit payments", .fixed, .monthly),
            ("Subscriptions", .fixed, .monthly),
            ("Childcare or school fees", .fixed, .monthly),
            ("Savings", .fixed, .monthly),
            ("Anything else fixed", .fixed, .monthly),

            ("Groceries", .steady, .weekly),
            ("Fuel or fares", .steady, .weekly),
            ("Household and toiletries", .steady, .monthly),
            ("Pets", .steady, .monthly),
            ("Anything else steady", .steady, .monthly),
        ]
        return specs.enumerated().map { index, spec in
            Line(id: index, label: spec.0, group: spec.1, period: spec.2)
        }
    }()

    /// What one entered amount comes to in a year.
    ///
    /// An empty or unparseable box is zero rather than an error: the form is
    /// seventeen prompts and most people will answer six of them. A comma is
    /// read as a decimal separator, which is the only thing it can be — the
    /// field is a decimal pad, so it cannot be a thousands grouping.
    public static func perYear(_ amount: String, _ period: Period) -> Double {
        parse(amount) * period.perYear
    }

    public static func parse(_ amount: String) -> Double {
        let trimmed = amount.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value.isFinite else { return 0 }
        return value
    }

    /// The answer: what is left each week once everything entered is accounted
    /// for.
    ///
    /// Can come out negative, and is returned that way. Rounding it up to zero
    /// would hide the only finding that matters — that the fixed costs as
    /// entered do not fit inside the income — behind a budget of nothing.
    public static func weekly(income: Double, outgoing: Double) -> Double {
        (income - outgoing) / weeksPerYear
    }

    /// Totals a filled-in form, keyed by ``Line/id``.
    public static func totals(amounts: [Int: String], periods: [Int: Period]) -> (income: Double, outgoing: Double) {
        var income = 0.0
        var outgoing = 0.0
        for line in lines {
            let value = perYear(amounts[line.id] ?? "", periods[line.id] ?? line.period)
            if line.group == .income { income += value } else { outgoing += value }
        }
        return (income, outgoing)
    }
}
