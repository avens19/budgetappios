import Foundation

/// Weeks and months as this app counts them.
///
/// A budget week does not start on Sunday, it starts on whichever weekday the
/// budget says — so none of Foundation's week helpers apply and the arithmetic
/// is done here instead. Everything is UTC, because a budget "day" is a
/// calendar day rather than an instant and must not move when the phone
/// crosses a timezone.
public struct BudgetCalendar: Sendable {

    /// 0 = Sunday, matching `Budget.StartDay` on the wire and `Calendar`'s
    /// 1-based `weekday` minus one.
    public let startDay: Int

    public init(startDay: Int) {
        self.startDay = ((startDay % 7) + 7) % 7
    }

    private var utc: Calendar { WireDate.utc }

    /// The first day of the budget week containing `date`.
    public func weekStart(containing date: Date) -> Date {
        let day = utc.startOfDay(for: date)
        let weekday = utc.component(.weekday, from: day) - 1   // 0 = Sunday
        let back = ((weekday - startDay) + 7) % 7
        return utc.date(byAdding: .day, value: -back, to: day)!
    }

    /// Exclusive: the first day of the following week.
    public func weekEnd(containing date: Date) -> Date {
        utc.date(byAdding: .day, value: 7, to: weekStart(containing: date))!
    }

    public func addingWeeks(_ count: Int, to date: Date) -> Date {
        utc.date(byAdding: .day, value: 7 * count, to: date)!
    }

    public func monthStart(containing date: Date) -> Date {
        let c = utc.dateComponents([.year, .month], from: date)
        return utc.date(from: DateComponents(year: c.year, month: c.month, day: 1))!
    }

    public func addingMonths(_ count: Int, to date: Date) -> Date {
        utc.date(byAdding: .month, value: count, to: monthStart(containing: date))!
    }

    /// The budget weeks that make up a month, as the Month tab shows them.
    ///
    /// The first one is the budget week containing the 1st, which usually
    /// starts in the previous month; the run continues while a week *begins*
    /// inside the month. This is the same span the Android and web clients add
    /// up, and the three have to agree or the same month shows three different
    /// totals on three devices.
    public func weeks(inMonthContaining date: Date) -> [Date] {
        let month = monthStart(containing: date)
        let monthNumber = utc.component(.month, from: month)

        var result = [weekStart(containing: month)]
        var next = addingWeeks(1, to: result[0])
        while utc.component(.month, from: next) == monthNumber {
            result.append(next)
            next = addingWeeks(1, to: next)
        }
        return result
    }

    public func isSameDay(_ a: Date, _ b: Date) -> Bool {
        utc.isDate(a, inSameDayAs: b)
    }

    public func isInMonth(_ date: Date, monthContaining other: Date) -> Bool {
        let a = utc.dateComponents([.year, .month], from: date)
        let b = utc.dateComponents([.year, .month], from: other)
        return a.year == b.year && a.month == b.month
    }

    /// Whole days from `date` to the last day of its week, inclusive of today.
    /// Drives "3 days left"; zero means today is the last day.
    public func daysLeftInWeek(from date: Date) -> Int {
        let start = weekStart(containing: date)
        let last = utc.date(byAdding: .day, value: 6, to: start)!
        return utc.dateComponents([.day], from: utc.startOfDay(for: date), to: last).day ?? 0
    }

    /// "Today" as a UTC calendar day.
    ///
    /// The device's own date in its own zone, then reinterpreted as UTC — so a
    /// phone in Auckland on the 17th gets the 17th, not the 16th. Reading
    /// `Date()` through the UTC calendar directly would give the wrong day for
    /// most of the world for part of every day.
    public static func today(now: Date = Date(), zone: TimeZone = .current) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let c = local.dateComponents([.year, .month, .day], from: now)
        return WireDate.utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
    }
}
