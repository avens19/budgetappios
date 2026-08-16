import Foundation
import BudgetCore

private func day(_ text: String) -> Date { try! WireDate.day(from: text) }

enum BudgetCalendarTests {

    /// A week starts on the budget's own weekday, not Sunday
    static func test_weekStartRespectsStartDay() {
        // 2026-08-13 is a Thursday.
        XCTAssertTrue(BudgetCalendar(startDay: 0).weekStart(containing: day("2026-08-13")) == day("2026-08-09"))
        XCTAssertTrue(BudgetCalendar(startDay: 1).weekStart(containing: day("2026-08-13")) == day("2026-08-10"))
        XCTAssertTrue(BudgetCalendar(startDay: 4).weekStart(containing: day("2026-08-13")) == day("2026-08-13"))
        XCTAssertTrue(BudgetCalendar(startDay: 5).weekStart(containing: day("2026-08-13")) == day("2026-08-07"))
    }

    /// A day that is itself the start day stays put
    static func test_startDayIsItsOwnWeekStart() {
        let calendar = BudgetCalendar(startDay: 1)          // Monday
        XCTAssertTrue(calendar.weekStart(containing: day("2026-08-10")) == day("2026-08-10"))
    }

    /// The week is seven days, end exclusive
    static func test_weekEndIsExclusive() {
        let calendar = BudgetCalendar(startDay: 0)
        XCTAssertTrue(calendar.weekEnd(containing: day("2026-08-13")) == day("2026-08-16"))
    }

    /// Weeks in a month begin with the week containing the 1st
    static func test_monthWeeks() {
        // August 2026: the 1st is a Saturday, so a Sunday budget's first week
        // starts on 26 July.
        let weeks = BudgetCalendar(startDay: 0).weeks(inMonthContaining: day("2026-08-16"))
        XCTAssertTrue(weeks.first == day("2026-07-26"))
        XCTAssertTrue(weeks.contains(day("2026-08-30")))
        // Only weeks that *begin* in August continue the run.
        XCTAssertTrue(!weeks.contains(day("2026-09-06")))
        XCTAssertTrue(weeks.count == 6)
    }

    /// Stepping across a month boundary lands on the first
    static func test_monthStepping() {
        let calendar = BudgetCalendar(startDay: 0)
        XCTAssertTrue(calendar.addingMonths(1, to: day("2026-12-15")) == day("2027-01-01"))
        XCTAssertTrue(calendar.addingMonths(-1, to: day("2026-01-15")) == day("2025-12-01"))
    }

    /// Days left counts today as remaining and zero on the last day
    static func test_daysLeft() {
        let calendar = BudgetCalendar(startDay: 0)          // week is 9th–15th
        XCTAssertTrue(calendar.daysLeftInWeek(from: day("2026-08-09")) == 6)
        XCTAssertTrue(calendar.daysLeftInWeek(from: day("2026-08-13")) == 2)
        XCTAssertTrue(calendar.daysLeftInWeek(from: day("2026-08-15")) == 0)
    }

    /// Today is the local calendar day, not the UTC instant
    static func test_todayUsesLocalDay() {
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

        // Mid-morning UTC: both sides of the world agree on the date.
        let morning = Date(timeIntervalSince1970: 1_787_216_400)   // 2026-08-20T09:00:00Z
        XCTAssertTrue(BudgetCalendar.today(now: morning, zone: auckland) == day("2026-08-20"))
        XCTAssertTrue(BudgetCalendar.today(now: morning, zone: losAngeles) == day("2026-08-20"))

        // Late UTC evening: Auckland has already rolled over and Los Angeles
        // has not. Reading Date() through a UTC calendar would give both the
        // 20th and put an Auckland expense in yesterday's week for the last
        // twelve hours of every day.
        let evening = Date(timeIntervalSince1970: 1_787_260_800)   // 2026-08-20T21:20:00Z
        XCTAssertTrue(BudgetCalendar.today(now: evening, zone: auckland) == day("2026-08-21"))
        XCTAssertTrue(BudgetCalendar.today(now: evening, zone: losAngeles) == day("2026-08-20"))
    }
}

enum WireDateTests {

    /// A day survives the round trip
    static func test_roundTrip() throws {
        try XCTAssertTrue(WireDate.string(from: try WireDate.day(from: "2026-08-14T00:00:00Z")) == "2026-08-14")
        try XCTAssertTrue(WireDate.string(from: try WireDate.day(from: "2026-08-14")) == "2026-08-14")
    }

    /// Parsing is lenient about what follows the date, as Android is
    static func test_lenientParsing() throws {
        let expected = try WireDate.day(from: "2026-08-14")
        try XCTAssertTrue(try WireDate.day(from: "2026-08-14T00:00:00Z") == expected)
        try XCTAssertTrue(try WireDate.day(from: "2026-08-14T13:45:12.345Z") == expected)
    }

    /// Rubbish is rejected rather than silently becoming 1970
    static func test_rejectsGarbage() {
        XCTAssertThrowsError(try WireDate.day(from: ""))
        XCTAssertThrowsError(try WireDate.day(from: "not-a-date"))
    }

    /// An expense decodes from the server's actual payload
    static func test_decodesServerPayload() throws {
        let json = """
        {"Budget":null,"Category":null,"Id":3293007,"Date":"2026-08-16T00:00:00Z",
         "Description":"Farmfoods","Amount":16.13,
         "BudgetId":"74b5fd14-2972-4378-ac17-9c72f3746855","CategoryId":null,
         "DateCreated":"2026-08-16T14:58:58Z","DateUpdated":"2026-08-16T14:58:58Z",
         "IsDeleted":false,"IsSystem":false}
        """
        let expense = try JSONDecoder().decode(WireExpense.self, from: Data(json.utf8))
        XCTAssertTrue(expense.id == 3_293_007)
        XCTAssertTrue(expense.description == "Farmfoods")
        XCTAssertTrue(expense.amount == 16.13)
        XCTAssertTrue(expense.categoryId == nil)
        let expectedDay = try WireDate.day(from: "2026-08-16")
        XCTAssertTrue(expense.date == expectedDay)
    }

    /// A null IsSystem reads as false, as it always has
    static func test_nullFlagsDefaultToFalse() throws {
        let json = """
        {"Id":1,"Date":"2026-08-16T00:00:00Z","Description":"x","Amount":1,
         "BudgetId":"b","IsDeleted":null,"IsSystem":null}
        """
        let expense = try JSONDecoder().decode(WireExpense.self, from: Data(json.utf8))
        XCTAssertTrue(expense.isSystem == false)
        XCTAssertTrue(expense.isDeleted == false)
    }

    /// Encoding sends a bare day, which no timezone can shift
    static func test_encodesBareDay() throws {
        let expense = WireExpense(id: 0, date: try WireDate.day(from: "2026-08-14"),
                                  description: "x", amount: 1, budgetId: "b")
        let text = String(decoding: try JSONEncoder().encode(expense), as: UTF8.self)
        XCTAssertTrue(text.contains("\"Date\":\"2026-08-14\""))
        XCTAssertTrue(text.contains("\"BudgetId\":\"b\""))
    }
}
