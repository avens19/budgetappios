import Foundation

/// The sum behind carrying a week's balance into the next one.
///
/// A carry is an expense on the first day of the following week, flagged as
/// system, whose amount is the negative of what was left. So a surplus lowers
/// next week's spending and a deficit — a positive amount — raises it. Android
/// and the website write exactly the same row, which is how all three read each
/// other's carries.
///
/// It lives in Core, with nothing from SwiftUI or SwiftData in it, so the sum
/// can be tested from the command line like the rest of this package.
public enum CarryOver {

    /// The amount of the carry expense, or nil when there is nothing worth
    /// writing.
    ///
    /// Under a cent either way is rounding noise, and a "Carried Balance" row
    /// of $0.00 is clutter.
    public static func amount(limit: Double, spent: Double) -> Double? {
        let left = ((limit - spent) * 100).rounded() / 100
        guard abs(left) >= 0.01 else { return nil }
        return -left
    }
}
