import Foundation
import BudgetCore

enum WeeklyNumberTests {

    /// Every cycle becomes a yearly figure before anything is compared
    static func test_annualisesEachPeriod() {
        XCTAssertEqual(WeeklyNumber.perYear("100", .weekly), 5200)
        XCTAssertEqual(WeeklyNumber.perYear("100", .fortnightly), 2600)
        XCTAssertEqual(WeeklyNumber.perYear("100", .semiMonthly), 2400)
        XCTAssertEqual(WeeklyNumber.perYear("100", .monthly), 1200)
        XCTAssertEqual(WeeklyNumber.perYear("100", .yearly), 100)
    }

    /// The prompts are all optional, so most of them arrive empty; that is zero,
    /// not an error
    static func test_treatsUnusableAmountsAsNothing() {
        for text in ["", "   ", ".", "twelve", "inf", "nan"] {
            XCTAssertEqual(WeeklyNumber.perYear(text, .monthly), 0, "\"\(text)\" should count as nothing")
        }
    }

    /// Some keyboards give a comma for the decimal separator
    static func test_readsACommaDecimalSeparator() {
        XCTAssertEqual(WeeklyNumber.perYear("12,50", .monthly), 150)
    }

    /// The headline sum: pay fortnightly, bills monthly, insurance yearly — the
    /// three cycles that make "a month is four weeks" wrong
    static func test_dividesWhatIsLeftAcrossFiftyTwoWeeks() {
        let income = WeeklyNumber.perYear("2000", .fortnightly)
        let outgoing = WeeklyNumber.perYear("1500", .monthly) + WeeklyNumber.perYear("1200", .yearly)

        XCTAssertEqual(income, 52000)
        XCTAssertEqual(outgoing, 19200)
        XCTAssertTrue(abs(WeeklyNumber.weekly(income: income, outgoing: outgoing) - 630.769230) < 0.000001)
    }

    /// Spending more than you earn is the finding this exists to surface, so it
    /// is reported rather than floored at zero
    static func test_reportsAShortfallAsNegative() {
        XCTAssertTrue(WeeklyNumber.weekly(income: 12000, outgoing: 24000) < 0)
    }

    /// Income adds, everything else subtracts, and a prompt with no answer
    /// contributes nothing
    static func test_totalsSplitIncomeFromOutgoing() {
        let pay = WeeklyNumber.lines.first { $0.label == "Take-home pay" }!
        let rent = WeeklyNumber.lines.first { $0.label == "Rent or mortgage" }!
        let groceries = WeeklyNumber.lines.first { $0.label == "Groceries" }!

        let totals = WeeklyNumber.totals(
            amounts: [pay.id: "2100", rent.id: "1450", groceries.id: "185"],
            periods: [:])

        XCTAssertEqual(totals.income, 54600)                     // 2100 × 26
        XCTAssertEqual(totals.outgoing, 17400 + 9620)            // 1450 × 12, 185 × 52
        XCTAssertTrue(abs(WeeklyNumber.weekly(income: totals.income, outgoing: totals.outgoing) - 530.3846) < 0.0001)
    }

    /// A period given for a line overrides the default it starts on
    static func test_totalsHonourAChangedPeriod() {
        let pay = WeeklyNumber.lines[0]
        let totals = WeeklyNumber.totals(amounts: [pay.id: "1000"], periods: [pay.id: .monthly])
        XCTAssertEqual(totals.income, 12000)
    }

    /// The three clients ask the same questions in the same order, so a number
    /// worked out on one is reproducible on the others
    static func test_asksSeventeenPromptsInThreeGroups() {
        XCTAssertEqual(WeeklyNumber.lines.count, 17)
        XCTAssertEqual(WeeklyNumber.lines.filter { $0.group == .income }.count, 2)
        XCTAssertEqual(WeeklyNumber.lines.filter { $0.group == .fixed }.count, 10)
        XCTAssertEqual(WeeklyNumber.lines.filter { $0.group == .steady }.count, 5)
        XCTAssertEqual(WeeklyNumber.lines[0].label, "Take-home pay")
        // Ids are positions, and a stored answer is read back by id.
        XCTAssertEqual(WeeklyNumber.lines.map(\.id), Array(0..<17))
    }
}
