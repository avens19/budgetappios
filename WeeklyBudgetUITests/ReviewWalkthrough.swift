import XCTest

/// Drives the app through its core flow at a watchable pace, so a screen
/// recording can be captured of a real device or simulator actually using it.
///
/// Not part of the normal suite — it is slow on purpose and asserts almost
/// nothing. Exclude it when running the others:
///
///     xcodebuild test ... -skip-testing:WeeklyBudgetUITests/ReviewWalkthrough
///
/// and run it on its own with the recorder going:
///
///     xcrun simctl io booted recordVideo walkthrough.mp4 &
///     xcodebuild test ... -only-testing:WeeklyBudgetUITests/ReviewWalkthrough
///
/// There is no environment gate because `TEST_RUNNER_`-prefixed variables did not
/// reach the runner in this Xcode, and a gate that silently skips is worse than
/// none. Its only side effect is one expense added to the disposable budget seeded
/// for App Review — joining is a read on the server, so nothing else is written.
///
/// The pauses are the point. A recording that moves at test speed is unreadable,
/// and the reviewer needs to see the remaining balance change when an expense is
/// added — which is the whole idea of the app.
final class ReviewWalkthrough: XCTestCase {

    /// The budget seeded for App Review, so the recording shows a populated week
    /// rather than an empty one.
    private let demoBudget = "72b1a062-bf95-48cb-bde1-bee2b528e200"

    private func beat(_ seconds: TimeInterval = 1.6) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func test_walkthrough() {
        let app = XCUIApplication()
        // A cold launch onto the real first-run screen: no demo seed and no stored
        // budget, which is what the reviewer will see when they open it.
        app.launchArguments = ["-resetStore", "-roomy"]
        app.launch()
        beat(2.5)

        // ---- first run: join the budget prepared for review -------------------
        let getStarted = app.buttons["Get started"]
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 5) {
            // Page through the four intro cards rather than skipping them: they say
            // what the app is for, which is question 3.
            for _ in 0..<3 where app.buttons["Next"].exists {
                app.buttons["Next"].tap()
                beat(1.2)
            }
            if getStarted.exists { getStarted.tap() } else { skip.tap() }
        }
        beat(1.8)

        app.buttons["Join"].tap()
        beat(1.2)

        let idField = app.textFields["Budget ID"]
        XCTAssertTrue(idField.waitForExistence(timeout: 5))
        idField.tap()
        idField.typeText(demoBudget)
        beat(1.2)
        app.buttons["Join budget"].tap()

        // ---- the week ---------------------------------------------------------
        XCTAssertTrue(app.staticTexts["Left to spend"].waitForExistence(timeout: 20),
                      "the joined budget should load")
        beat(3.0)

        // ---- add an expense, and watch the balance move -----------------------
        app.buttons["addExpense"].tap()
        beat(1.5)

        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("12.50")
        beat(0.8)
        app.textFields["descriptionField"].tap()
        app.textFields["descriptionField"].typeText("Lunch")
        beat(1.0)
        app.buttons["saveExpense"].tap()
        // The remaining total changes here. Hold on it.
        beat(3.5)

        // ---- the other two tabs ----------------------------------------------
        tab(app, "month").tap()
        beat(3.0)
        tab(app, "categories").tap()
        beat(3.5)
        tab(app, "week").tap()
        beat(1.5)

        // ---- settings, sharing, and About -------------------------------------
        app.buttons["budgetSettings"].tap()
        beat(3.0)

        var attempts = 0
        let about = app.buttons["About"]
        while !about.exists && attempts < 6 {
            app.swipeUp()
            beat(0.6)
            attempts += 1
        }
        if about.exists {
            about.tap()
            beat(3.5)
        }
    }

    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let byIdentifier = app.descendants(matching: .any)["tab.\(name)"].firstMatch
        return byIdentifier.exists ? byIdentifier : app.tabBars.buttons[name.capitalized]
    }
}
