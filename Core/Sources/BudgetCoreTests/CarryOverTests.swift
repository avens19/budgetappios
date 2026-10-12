import Foundation
import BudgetCore

enum CarryOverTests {

    /// A surplus carries as a negative expense, which lowers next week's spend
    static func test_aSurplusCarriesAsANegativeExpense() {
        XCTAssertEqual(CarryOver.amount(limit: 200, spent: 75.5), -124.5)
    }

    /// The request that started this: a deficit has to follow the reader too,
    /// as a positive expense that uses some of the new week up
    static func test_aDeficitCarriesAsAPositiveExpense() {
        XCTAssertEqual(CarryOver.amount(limit: 100, spent: 125.25), 25.25)
    }

    static func test_anEvenWeekCarriesNothing() {
        XCTAssertNil(CarryOver.amount(limit: 100, spent: 100))
        XCTAssertNil(CarryOver.amount(limit: 100, spent: 33.33 + 66.67))
    }

    /// 0.1 + 0.2 is 0.30000000000000004, and a $0.00 carry is clutter
    static func test_ignoresRoundingNoise() {
        XCTAssertNil(CarryOver.amount(limit: 0.3, spent: 0.1 + 0.2))
        XCTAssertNil(CarryOver.amount(limit: 100, spent: 99.996))
    }

    static func test_roundsToTheCent() {
        XCTAssertEqual(CarryOver.amount(limit: 10, spent: 3.333), -6.67)
    }

    static func test_anEmptyWeekCarriesTheWholeAllowance() {
        XCTAssertEqual(CarryOver.amount(limit: 120, spent: 0), -120)
    }
}
