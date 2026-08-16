import XCTest

/// The flows that only exist as taps.
///
/// The sync engine and the calendar maths are covered by BudgetCore's own
/// suite, which runs without a simulator. What is left is everything a person
/// does with their thumb: the add sheet, swipe to delete, the carry
/// confirmation, the category picker. Those had never been exercised.
///
/// Every test launches with `-demo`, which seeds a local budget and never
/// touches the network, so these are deterministic and safe to run in a loop.
final class InteractionTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// A row is a Button labelled "Detail, Category, $Amount" — the children
    /// are combined, so it cannot be found by a child's identifier.
    private func row(_ app: XCUIApplication, _ detail: String) -> XCUIElement {
        let element = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", detail)).firstMatch
        // A SwiftUI List is lazy: rows below the fold are not in the
        // accessibility tree at all, so scroll until one appears rather than
        // reporting it missing.
        var attempts = 0
        while !element.exists && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        return element
    }

    private func launch(tab: String = "week", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-tab", tab] + extra
        // A fresh store per test: otherwise one test's new expense changes the
        // totals the next one asserts on.
        app.launchArguments += ["-resetStore"]
        app.launch()
        return app
    }

    // MARK: Adding

    func test_addExpense_appearsInTheListAndMovesTheTotal() {
        let app = launch()

        let hero = app.staticTexts["Left to spend"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "week view should load")

        app.buttons["addExpense"].tap()

        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "the add sheet should open")
        // The amount field is focused on open, so typing goes straight in — the
        // one thing that always has to be typed should not need a tap first.
        XCTAssertTrue(amount.value as? String == "" || amount.hasKeyboardFocus,
                      "amount should be focused on open")
        amount.tap()
        amount.typeText("18.25")

        app.textFields["descriptionField"].tap()
        app.textFields["descriptionField"].typeText("Hardware store")

        app.buttons["saveExpense"].tap()

        XCTAssertTrue(app.staticTexts["Hardware store"].waitForExistence(timeout: 5),
                      "the new expense should be in the week list")
    }

    func test_saveIsBlockedUntilBothFieldsAreFilled() {
        let app = launch()
        app.buttons["addExpense"].tap()

        let save = app.buttons["saveExpense"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "save should be off with nothing entered")

        let amount = app.textFields["amountField"]
        amount.tap()
        amount.typeText("5")
        XCTAssertFalse(save.isEnabled, "an amount alone is not enough")

        app.textFields["descriptionField"].tap()
        app.textFields["descriptionField"].typeText("Tea")
        XCTAssertTrue(save.isEnabled, "amount plus description should enable save")
    }

    func test_negativeAmountIsAccepted() {
        // Income is entered as a negative expense; that is the whole model.
        let app = launch()
        app.buttons["addExpense"].tap()

        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("-40")
        app.textFields["descriptionField"].tap()
        app.textFields["descriptionField"].typeText("Refund")
        app.buttons["saveExpense"].tap()

        XCTAssertTrue(app.staticTexts["Refund"].waitForExistence(timeout: 5))
    }

    // MARK: Editing

    func test_tappingARowOpensItForEditing() {
        let app = launch()
        let row = row(app, "Big shop")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        // The amount field is the reliable signal that the editor is up; the
        // navigation bar's identifier is not always the title.
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5),
                      "tapping a row should open the editor")
        XCTAssertEqual(app.textFields["amountField"].value as? String, "84.2",
                       "the editor should be populated with the row's amount")
        XCTAssertTrue(app.buttons["Delete expense"].exists, "edit should offer delete")
        XCTAssertTrue(app.buttons["Copy to next week"].exists, "edit should offer copy")
    }

    func test_deleteFromTheEditSheetRemovesTheRow() {
        let app = launch()
        let row = row(app, "Cinema")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5),
                      "the editor should open")
        app.buttons["Delete expense"].tap()
        // Scope the confirmation to the dialog, or this matches the
        // "Delete expense" button still on the sheet behind it.
        let confirm = app.sheets.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "delete should confirm first")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["Cinema"].waitForNonExistence(timeout: 5),
                      "the deleted expense should be gone from the list")
    }

    func test_swipeToDeleteRemovesTheRow() {
        let app = launch()
        let row = row(app, "Coffee")
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        row.swipeLeft()
        // The revealed action lives in the row's own cell; a bare "Delete"
        // query can match a different row's.
        let delete = app.buttons.matching(
            NSPredicate(format: "label == %@", "Delete")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "swipe should reveal Delete")
        delete.tap()

        XCTAssertTrue(app.staticTexts["Coffee"].waitForNonExistence(timeout: 5))
    }

    // MARK: Carry balance

    func test_carryBalanceConfirmsBeforeWriting() {
        let app = launch()
        let carry = app.buttons["carryBalance"].firstMatch
        XCTAssertTrue(carry.waitForExistence(timeout: 10))
        carry.tap()

        // Cancel first: a money-moving action should not fire on one tap.
        // The confirmation is an action sheet, the same shape the delete
        // confirmation uses.
        let confirm = app.sheets.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Move ")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 4),
                      "carry should confirm before moving money")

        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        // The carried row lands in *next* week, so this week is unchanged and
        // stepping forward should show it.
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Carried Balance"].waitForExistence(timeout: 5),
                      "the carried balance should appear in the following week")
    }

    // MARK: Categories

    func test_categoryPickerOffersTheBudgetsCategories() {
        let app = launch()
        app.buttons["addExpense"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))

        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Category")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "the category picker should be present")
        picker.tap()
        XCTAssertTrue(app.buttons["Groceries"].waitForExistence(timeout: 3),
                      "the picker should list the budget's categories")
        XCTAssertTrue(app.buttons["No category"].exists)
    }

    func test_newCategoryCanBeCreatedWhileAddingAnExpense() {
        let app = launch()
        app.buttons["addExpense"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))

        app.buttons["New category"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Hobbies")
        app.alerts.buttons["Add"].tap()

        // The picker row carries the selected value in its label.
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Category")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertTrue(picker.label.contains("Hobbies"),
                      "the new category should be selected, got: " + picker.label)
    }

    func test_categoriesTabShowsTheBreakdownAndSelects() {
        let app = launch(tab: "categories")

        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 10),
                      "the legend should list categories")
        XCTAssertTrue(app.staticTexts["Tap a category to see its expenses."].exists)

        let legendRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Groceries")).firstMatch
        XCTAssertTrue(legendRow.waitForExistence(timeout: 5), "Groceries should be in the legend")
        legendRow.tap()

        // Its expenses appear in a section below, which needs scrolling to.
        var attempts = 0
        while !app.staticTexts["Big shop"].exists && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(app.staticTexts["Big shop"].exists,
                      "selecting a category should reveal its expenses")
    }

    func test_managingCategoriesRenames() {
        let app = launch(tab: "categories")
        XCTAssertTrue(app.buttons["Manage"].waitForExistence(timeout: 10))
        app.buttons["Manage"].tap()

        let entry = app.cells.containing(.staticText, identifier: "Fun").firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Fun should be listed")
        entry.swipeLeft()
        app.buttons["Rename"].tap()

        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.clearAndType("Leisure")
        app.alerts.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Leisure"].waitForExistence(timeout: 5))
    }

    // MARK: Navigation

    func test_tabsSwitchBetweenTheThreeScreens() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Left to spend"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Month"].tap()
        XCTAssertTrue(app.staticTexts["Spent this month"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Categories"].tap()
        XCTAssertTrue(app.staticTexts["Tap a category to see its expenses."]
            .waitForExistence(timeout: 5))

        app.tabBars.buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["Left to spend"].waitForExistence(timeout: 5))
    }

    func test_steppingWeeksShowsTodayAndComesBack() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Left to spend"].waitForExistence(timeout: 10))
        // Today is always offered and disabled while it would do nothing.
        let today = app.buttons["Today"]
        XCTAssertTrue(today.exists, "Today should be present")
        XCTAssertFalse(today.isEnabled, "Today should be disabled on the current week")

        let thisWeek = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "This week")).firstMatch
        XCTAssertTrue(thisWeek.exists, "the current week should say so")

        app.buttons["Previous"].tap()
        XCTAssertTrue(thisWeek.waitForNonExistence(timeout: 3),
                      "stepping back should leave the current week")

        today.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "This week"))
            .firstMatch.waitForExistence(timeout: 3),
                      "Today should come back to the current week")
    }

    func test_settingsShowsTheBudgetIdForSharing() {
        let app = launch()
        XCTAssertTrue(app.buttons["budgetSettings"].waitForExistence(timeout: 10))
        app.buttons["budgetSettings"].tap()

        XCTAssertTrue(app.staticTexts["Budget ID"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share budget ID"].exists)
        XCTAssertTrue(app.buttons["How this works"].exists)
    }
}

// MARK: - Accessibility

final class AccessibilityTests: XCTestCase {

    /// The largest accessibility type size. Layouts that only work at the
    /// default size fall apart here, and this is where truncation shows up.
    func test_readableAtTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-tab", "week", "-resetStore",
                               "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Left to spend"].waitForExistence(timeout: 10),
                      "the hero label should survive the largest text size")
        XCTAssertTrue(app.buttons["addExpense"].exists, "the toolbar should still be usable")
        XCTAssertTrue(app.tabBars.buttons["Month"].exists, "tabs should still be reachable")
    }

    /// Everything interactive needs a label, or VoiceOver announces "button".
    func test_controlsAreLabelledForVoiceOver() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-tab", "week", "-resetStore"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Left to spend"].waitForExistence(timeout: 10))

        for identifier in ["addExpense", "budgetSettings"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.exists, "\(identifier) should exist")
            XCTAssertFalse(control.label.isEmpty, "\(identifier) needs an accessibility label")
        }

        // The hero is one combined element rather than four fragments, so
        // VoiceOver reads a sentence instead of stray numbers.
        let hero = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "left to spend")).firstMatch
        XCTAssertTrue(hero.exists, "the hero should be a single labelled element")

        // And the carry action must survive as its own control rather than
        // being absorbed into that combined element.
        XCTAssertEqual(app.buttons.matching(identifier: "carryBalance").count, 1,
                       "carryBalance should be exactly one reachable button")
    }
}

// MARK: - Helpers

extension XCUIElement {
    var hasKeyboardFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    func clearAndType(_ text: String) {
        tap()
        if let existing = value as? String, !existing.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        typeText(text)
    }

    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !exists { return true }
            usleep(100_000)
        }
        return !exists
    }
}
