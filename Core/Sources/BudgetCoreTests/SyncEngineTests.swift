import Foundation
import BudgetCore

// MARK: - Doubles

/// Records what the engine asked for, and lets a test answer however it likes.
actor FakeAPI: BudgetAPI {
    var remoteBudget: WireBudget?
    var expensePage = Page<WireExpense>(items: [], watermark: nil)
    var categoryPage = Page<WireCategory>(items: [], watermark: nil)
    var nextServerId: Int64 = 500

    private(set) var calls: [String] = []
    private(set) var watermarksRequested: [String?] = []

    init(remoteBudget: WireBudget? = nil) { self.remoteBudget = remoteBudget }

    func set(expenses: Page<WireExpense>) { expensePage = expenses }
    func set(categories: Page<WireCategory>) { categoryPage = categories }

    func budget(id: String) async throws -> WireBudget? { remoteBudget }
    func createBudget(_ budget: WireBudget) async throws -> WireBudget { budget }
    func updateBudget(_ budget: WireBudget) async throws { calls.append("updateBudget") }

    func expenses(budgetId: String, since: String?) async throws -> Page<WireExpense> {
        watermarksRequested.append(since)
        calls.append("getExpenses")
        return expensePage
    }

    func categories(budgetId: String, since: String?) async throws -> Page<WireCategory> {
        watermarksRequested.append(since)
        calls.append("getCategories")
        return categoryPage
    }

    func createExpense(_ expense: WireExpense) async throws -> WireExpense {
        calls.append("createExpense(\(expense.id))")
        var saved = expense
        saved.id = nextServerId
        nextServerId += 1
        return saved
    }

    func updateExpense(_ expense: WireExpense) async throws { calls.append("updateExpense(\(expense.id))") }

    func deleteExpense(id: Int64) async throws -> WireExpense {
        calls.append("deleteExpense(\(id))")
        return WireExpense(id: id, date: Date(), description: "", amount: 0, budgetId: "b", isDeleted: true)
    }

    func createCategory(_ category: WireCategory) async throws -> WireCategory {
        calls.append("createCategory(\(category.id))")
        var saved = category
        saved.id = nextServerId
        nextServerId += 1
        return saved
    }

    func updateCategory(_ category: WireCategory) async throws { calls.append("updateCategory(\(category.id))") }

    func deleteCategory(id: Int64) async throws -> WireCategory {
        calls.append("deleteCategory(\(id))")
        return WireCategory(id: id, name: "gone", budgetId: "b", isDeleted: true)
    }
}

actor FakeStore: LocalStore {
    var storedWatermark: String?
    var pendingE: [Pending<WireExpense>] = []
    var pendingC: [Pending<WireCategory>] = []

    private(set) var applied: [String] = []
    private(set) var watermarkWrites: [String] = []

    init(watermark: String? = nil) { storedWatermark = watermark }

    func set(pendingExpenses: [Pending<WireExpense>]) { pendingE = pendingExpenses }
    func set(pendingCategories: [Pending<WireCategory>]) { pendingC = pendingCategories }

    func watermark(budgetId: String) async throws -> String? { storedWatermark }

    func setWatermark(_ watermark: String, budgetId: String) async throws {
        storedWatermark = watermark
        watermarkWrites.append(watermark)
    }

    func updateBudgetDetails(_ budget: WireBudget) async throws { applied.append("budget(\(budget.name))") }
    func pendingExpenses(budgetId: String) async throws -> [Pending<WireExpense>] { pendingE }
    func pendingCategories(budgetId: String) async throws -> [Pending<WireCategory>] { pendingC }
    func applyIncoming(_ expense: WireExpense) async throws { applied.append("expense(\(expense.id))") }
    func applyIncoming(_ category: WireCategory) async throws { applied.append("category(\(category.id))") }
    func replaceExpense(localId: Int64, with saved: WireExpense) async throws {
        applied.append("replaceExpense(\(localId)->\(saved.id))")
    }
    func replaceCategory(localId: Int64, with saved: WireCategory) async throws {
        applied.append("replaceCategory(\(localId)->\(saved.id))")
    }
    func markExpenseSynced(id: Int64) async throws { applied.append("syncedExpense(\(id))") }
    func markCategorySynced(id: Int64) async throws { applied.append("syncedCategory(\(id))") }
    func removeExpense(id: Int64) async throws { applied.append("removeExpense(\(id))") }
}

private func expense(_ id: Int64, _ description: String = "x") -> WireExpense {
    WireExpense(id: id, date: try! WireDate.day(from: "2026-08-16"),
                description: description, amount: 1, budgetId: "b")
}

// MARK: - Watermark

enum WatermarkTests {

    /// The earlier of the two feeds wins
    static func test_takesEarlier() {
        let early = "2026-08-16T15:00:00.0000000Z"
        let late  = "2026-08-16T15:00:01.0000000Z"
        XCTAssertTrue(SyncEngine.nextWatermark(early, late) == early)
        XCTAssertTrue(SyncEngine.nextWatermark(late, early) == early)
    }

    /// A missing header means do not advance at all
    static func test_missingHeaderMeansNil() {
        XCTAssertTrue(SyncEngine.nextWatermark(nil, "2026-08-16T15:00:00.0000000Z") == nil)
        XCTAssertTrue(SyncEngine.nextWatermark("2026-08-16T15:00:00.0000000Z", nil) == nil)
        XCTAssertTrue(SyncEngine.nextWatermark(nil, nil) == nil)
    }

    /// Equal watermarks are returned unchanged
    static func test_equalIsFine() {
        let same = "2026-08-16T15:00:00.0000000Z"
        XCTAssertTrue(SyncEngine.nextWatermark(same, same) == same)
    }

    /// String ordering matches time ordering at fixed width
    static func test_lexicographicOrderingHolds() {
        // The whole scheme rests on this. Every pair below is ordered the same
        // way as text and as time, which is only true while the fraction is
        // padded to a fixed seven digits.
        let ordered = [
            "2026-08-16T09:00:00.0000000Z",
            "2026-08-16T09:00:00.0000001Z",
            "2026-08-16T09:00:00.1000000Z",
            "2026-08-16T09:00:01.0000000Z",
            "2026-08-16T10:00:00.0000000Z",
            "2026-09-01T00:00:00.0000000Z",
            "2027-01-01T00:00:00.0000000Z",
        ]
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            XCTAssertTrue(a < b, "\(a) should sort before \(b)")
            XCTAssertTrue(SyncEngine.nextWatermark(a, b) == a)
        }
    }
}

// MARK: - Engine

enum SyncEngineTests {

    /// Pulls with the watermark held before pushing, not after
    static func test_pullsFromTheStoredWatermark() async throws {
        let stored = "2026-08-16T12:00:00.0000000Z"
        let api = FakeAPI()
        let store = FakeStore(watermark: stored)
        await store.set(pendingExpenses: [Pending(value: expense(1), state: .edited)])

        try await SyncEngine(api: api, store: store).sync(budgetId: "b")

        // Both feeds asked for exactly the watermark we started with. Reading it
        // after the push would move the window past our own writes.
        let requested = await api.watermarksRequested
        XCTAssertTrue(requested == [stored, stored])
    }

    /// A created row is sent, then replaced by the server's copy
    static func test_createdRowsAreReplaced() async throws {
        let api = FakeAPI()
        let store = FakeStore()
        await store.set(pendingExpenses: [
            Pending(value: expense(LocalIds.firstLocalId), state: .created)
        ])

        try await SyncEngine(api: api, store: store).sync(budgetId: "b")

        let applied = await store.applied
        XCTAssertTrue(applied.contains("replaceExpense(1000000000000->500)"))
    }

    /// Deleting a row the server never saw skips the network
    static func test_localOnlyDeleteSkipsTheServer() async throws {
        let api = FakeAPI()
        let store = FakeStore()
        await store.set(pendingExpenses: [
            Pending(value: expense(LocalIds.firstLocalId + 7), state: .deleted)
        ])

        try await SyncEngine(api: api, store: store).sync(budgetId: "b")

        // A DELETE for an id the server has never issued would 404 and abort
        // the whole sync, stranding every later change behind it.
        let calls = await api.calls
        XCTAssertTrue(!calls.contains { $0.hasPrefix("deleteExpense") })
        let applied = await store.applied
        XCTAssertTrue(applied.contains("removeExpense(1000000007)") == false)
        XCTAssertTrue(applied.contains("removeExpense(\(LocalIds.firstLocalId + 7))"))
    }

    /// Deleting a synced row does call the server
    static func test_syncedDeleteHitsTheServer() async throws {
        let api = FakeAPI()
        let store = FakeStore()
        await store.set(pendingExpenses: [Pending(value: expense(42), state: .deleted)])

        try await SyncEngine(api: api, store: store).sync(budgetId: "b")

        let calls = await api.calls
        XCTAssertTrue(calls.contains("deleteExpense(42)"))
    }

    /// Categories are pushed before expenses
    static func test_categoriesGoFirst() async throws {
        let api = FakeAPI()
        let store = FakeStore()
        await store.set(pendingCategories: [
            Pending(value: WireCategory(id: LocalIds.firstLocalId, name: "New", budgetId: "b"), state: .created)
        ])
        await store.set(pendingExpenses: [
            Pending(value: expense(LocalIds.firstLocalId + 1), state: .created)
        ])

        try await SyncEngine(api: api, store: store).sync(budgetId: "b")

        // An expense can reference a category created in the same sync, so the
        // category needs its real id first.
        let calls = await api.calls
        let categoryIndex = calls.firstIndex { $0.hasPrefix("createCategory") }
        let expenseIndex = calls.firstIndex { $0.hasPrefix("createExpense") }
        XCTAssertTrue(categoryIndex != nil && expenseIndex != nil)
        XCTAssertTrue(categoryIndex! < expenseIndex!)
    }

    /// Incoming rows are applied before the watermark moves
    static func test_appliesBeforeAdvancing() async throws {
        let mark = "2026-08-16T15:00:00.0000000Z"
        let api = FakeAPI()
        await api.set(expenses: Page(items: [expense(7), expense(8)], watermark: mark))
        await api.set(categories: Page(items: [], watermark: mark))
        let store = FakeStore()

        try await SyncEngine(api: api, store: store).sync(budgetId: "b")

        let observed1 = await store.storedWatermark
        XCTAssertTrue(observed1 == mark)
        let applied = await store.applied
        XCTAssertTrue(applied.contains("expense(7)"))
        XCTAssertTrue(applied.contains("expense(8)"))
    }

    /// A feed with no header leaves the stored watermark untouched
    static func test_doesNotAdvanceWithoutAHeader() async throws {
        let stored = "2026-08-16T12:00:00.0000000Z"
        let api = FakeAPI()
        await api.set(expenses: Page(items: [expense(9)], watermark: nil))
        await api.set(categories: Page(items: [], watermark: "2026-08-16T15:00:00.0000000Z"))
        let store = FakeStore(watermark: stored)

        try await SyncEngine(api: api, store: store).sync(budgetId: "b")

        // The row is still applied — it just gets fetched again next time.
        let observed2 = await store.applied.contains("expense(9)")
        XCTAssertTrue(observed2)
        let observed3 = await store.storedWatermark
        XCTAssertTrue(observed3 == stored)
        let observed4 = await store.watermarkWrites.isEmpty
        XCTAssertTrue(observed4)
    }

    /// The stored watermark is the earlier of the two feeds
    static func test_storesTheEarlierWatermark() async throws {
        let earlier = "2026-08-16T15:00:00.0000000Z"
        let later = "2026-08-16T15:00:02.0000000Z"
        let api = FakeAPI()
        await api.set(categories: Page(items: [], watermark: earlier))
        await api.set(expenses: Page(items: [], watermark: later))
        let store = FakeStore()

        try await SyncEngine(api: api, store: store).sync(budgetId: "b")

        let observed5 = await store.storedWatermark
        XCTAssertTrue(observed5 == earlier)
    }
}

// MARK: - Palette

enum CategoryPaletteTests {

    private static let categories = [
        WireCategory(id: 30, name: "Transport", budgetId: "b"),
        WireCategory(id: 10, name: "Groceries", budgetId: "b"),
        WireCategory(id: 20, name: "Eating out", budgetId: "b"),
    ]

    /// Colour follows rank in id order, so it matches the other clients
    static func test_slotsByIdRank() {
        let palette = CategoryPalette(categories: categories)
        XCTAssertTrue(palette.slot(for: 10) == 0)
        XCTAssertTrue(palette.slot(for: 20) == 1)
        XCTAssertTrue(palette.slot(for: 30) == 2)
    }

    /// Uncategorised and unknown ids get no slot
    static func test_noSlotForUnknown() {
        let palette = CategoryPalette(categories: categories)
        XCTAssertTrue(palette.slot(for: nil) == nil)
        XCTAssertTrue(palette.slot(for: 999) == nil)
        XCTAssertTrue(palette.name(for: 999) == "Uncategorized")
    }

    /// More than ten categories wrap around the palette
    static func test_wrapsAtTen() {
        let many = (1...12).map { WireCategory(id: Int64($0), name: "c\($0)", budgetId: "b") }
        let palette = CategoryPalette(categories: many)
        XCTAssertTrue(palette.slot(for: 1) == 0)
        XCTAssertTrue(palette.slot(for: 11) == 0)
        XCTAssertTrue(palette.slot(for: 12) == 1)
    }

    /// Deleted categories are not in the palette at all
    static func test_deletedAreExcluded() {
        let palette = CategoryPalette(categories: [
            WireCategory(id: 10, name: "Groceries", budgetId: "b"),
            WireCategory(id: 20, name: "Gone", budgetId: "b", isDeleted: true),
            WireCategory(id: 30, name: "Transport", budgetId: "b"),
        ])
        // Ranking skips the deleted one, so Transport takes slot 1 not 2.
        XCTAssertTrue(palette.slot(for: 10) == 0)
        XCTAssertTrue(palette.slot(for: 30) == 1)
        XCTAssertTrue(palette.isKnown(20) == false)
    }

    /// System rows are left out of the chart
    static func test_breakdownExcludesSystemRows() {
        let palette = CategoryPalette(categories: categories)
        let slices = palette.breakdown(of: [
            WireExpense(id: 1, date: Date(), description: "Shop", amount: 50, budgetId: "b", categoryId: 10),
            WireExpense(id: 2, date: Date(), description: "Carried Balance", amount: -20,
                        budgetId: "b", categoryId: nil, isSystem: true),
        ])
        XCTAssertTrue(slices.count == 1)
        XCTAssertTrue(slices[0].amount == 50)
    }

    /// Only positive totals are charted
    static func test_breakdownDropsNegativeBuckets() {
        let palette = CategoryPalette(categories: categories)
        let slices = palette.breakdown(of: [
            WireExpense(id: 1, date: Date(), description: "Shop", amount: 50, budgetId: "b", categoryId: 10),
            WireExpense(id: 2, date: Date(), description: "Refund", amount: -80, budgetId: "b", categoryId: 20),
        ])
        let names = slices.map { $0.name }
        XCTAssertEqual(names, ["Groceries"])
    }

    /// An orphaned category id folds into Uncategorized rather than making a second bucket
    static func test_orphansJoinUncategorized() {
        let palette = CategoryPalette(categories: categories)
        let slices = palette.breakdown(of: [
            WireExpense(id: 1, date: Date(), description: "Cinema", amount: 22, budgetId: "b", categoryId: 777),
            WireExpense(id: 2, date: Date(), description: "Bits", amount: 10, budgetId: "b", categoryId: nil),
        ])
        // Two slices both labelled "Uncategorized" reads as a bug; this was a
        // real one on the web before it was caught.
        XCTAssertTrue(slices.count == 1)
        XCTAssertTrue(slices[0].name == "Uncategorized")
        XCTAssertTrue(slices[0].amount == 32)
    }

    /// Biggest first
    static func test_breakdownIsSortedDescending() {
        let palette = CategoryPalette(categories: categories)
        let slices = palette.breakdown(of: [
            WireExpense(id: 1, date: Date(), description: "a", amount: 10, budgetId: "b", categoryId: 10),
            WireExpense(id: 2, date: Date(), description: "b", amount: 90, budgetId: "b", categoryId: 20),
            WireExpense(id: 3, date: Date(), description: "c", amount: 50, budgetId: "b", categoryId: 30),
        ])
        let names = slices.map { $0.name }
        XCTAssertEqual(names, ["Eating out", "Transport", "Groceries"])
    }
}
