import Foundation

/// Push local changes, then pull everything new.
///
/// A direct port of the Android client's `Sync.run`, deliberately: the two
/// clients share budgets, so any disagreement about the protocol shows up as
/// one device silently missing the other's expenses.
///
/// The order is load-bearing in two places, both marked below.
public struct SyncEngine: Sendable {

    let api: any BudgetAPI
    let store: any LocalStore

    public init(api: any BudgetAPI, store: any LocalStore) {
        self.api = api
        self.store = store
    }

    @discardableResult
    public func sync(budgetId: String) async throws -> SyncOutcome {
        // Read before pushing. The pull window must start where the last sync
        // finished, and pushing our own rows moves the server clock forward.
        let watermark = try await store.watermark(budgetId: budgetId)

        if let remote = try await api.budget(id: budgetId) {
            try await store.updateBudgetDetails(remote)
        }

        try await pushCategories(budgetId: budgetId)
        try await pushExpenses(budgetId: budgetId)

        let categories = try await api.categories(budgetId: budgetId, since: watermark)
        let expenses = try await api.expenses(budgetId: budgetId, since: watermark)

        // Apply first, advance the watermark second. Crashing in between costs
        // one redundant re-fetch; the other order loses the changes for good.
        for category in categories.items {
            try await store.applyIncoming(category)
        }
        for expense in expenses.items {
            try await store.applyIncoming(expense)
        }

        if let next = Self.nextWatermark(categories.watermark, expenses.watermark) {
            try await store.setWatermark(next, budgetId: budgetId)
        }

        return SyncOutcome(categoriesPulled: categories.items.count,
                           expensesPulled: expenses.items.count,
                           watermark: Self.nextWatermark(categories.watermark, expenses.watermark))
    }

    private func pushCategories(budgetId: String) async throws {
        for pending in try await store.pendingCategories(budgetId: budgetId) {
            switch pending.state {
            case .created:
                let saved = try await api.createCategory(pending.value)
                try await store.replaceCategory(localId: pending.value.id, with: saved)
            case .edited:
                try await api.updateCategory(pending.value)
                try await store.markCategorySynced(id: pending.value.id)
            case .deleted:
                let saved = try await api.deleteCategory(id: pending.value.id)
                try await store.replaceCategory(localId: pending.value.id, with: saved)
                try await store.markCategorySynced(id: saved.id)
            }
        }
    }

    private func pushExpenses(budgetId: String) async throws {
        for pending in try await store.pendingExpenses(budgetId: budgetId) {
            switch pending.state {
            case .created:
                let saved = try await api.createExpense(pending.value)
                try await store.replaceExpense(localId: pending.value.id, with: saved)
            case .edited:
                try await api.updateExpense(pending.value)
                try await store.markExpenseSynced(id: pending.value.id)
            case .deleted:
                // Deleting something the server never saw would 404. It only
                // exists here, so dropping it locally is the whole job.
                if pending.value.id < LocalIds.firstLocalId {
                    _ = try await api.deleteExpense(id: pending.value.id)
                }
                try await store.removeExpense(id: pending.value.id)
            }
        }
    }

    /// The instant both feeds are complete up to.
    ///
    /// Never the device's own clock. The server compares this against
    /// timestamps from *its* clock, so any skew is silent data loss: a phone
    /// running a minute fast stores a watermark ahead of the server's real
    /// time, and anything another device wrote inside that minute is never
    /// handed over again. This bug was real on Android and cost changes.
    ///
    /// The two feeds are separate requests and so separate instants. One value
    /// is stored for both and it must be the *earlier*: the later one would
    /// skip anything written to the other collection between the two requests.
    /// The earlier one can only cause a small overlap next time, and
    /// re-applying a row already stored is a no-op.
    ///
    /// `nil` means the server sent no header — an old deployment, or a proxy
    /// that stripped it. The caller then leaves the stored watermark alone.
    /// Re-syncing the same window is wasteful but correct, and it is the only
    /// answer available that is not a guess.
    public static func nextWatermark(_ a: String?, _ b: String?) -> String? {
        guard let a, let b else { return nil }
        // Both are fixed-width UTC from the same server
        // ("yyyy-MM-ddTHH:mm:ss.fffffffZ"), so ordering as text orders
        // chronologically. This is only sound while the width is fixed.
        return a <= b ? a : b
    }
}

public struct SyncOutcome: Sendable, Equatable {
    public let categoriesPulled: Int
    public let expensesPulled: Int
    public let watermark: String?
}

// MARK: - Local ids

public enum LocalIds {
    /// Rows created offline need an id immediately, and it must not collide
    /// with a server id. The server's are a bigserial in the millions; Android
    /// starts its local counter at 10^12 and counts up, so this does too — a
    /// budget shared between the two must not hand out the same id twice.
    public static let firstLocalId: Int64 = 1_000_000_000_000
}

// MARK: - Collaborators

public enum PendingState: Sendable, Equatable {
    case created, edited, deleted
}

public struct Pending<Value: Sendable>: Sendable {
    public let value: Value
    public let state: PendingState

    public init(value: Value, state: PendingState) {
        self.value = value
        self.state = state
    }
}

public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    public let watermark: String?

    public init(items: [Item], watermark: String?) {
        self.items = items
        self.watermark = watermark
    }
}

public protocol BudgetAPI: Sendable {
    func budget(id: String) async throws -> WireBudget?
    func createBudget(_ budget: WireBudget) async throws -> WireBudget
    func updateBudget(_ budget: WireBudget) async throws

    func expenses(budgetId: String, since: String?) async throws -> Page<WireExpense>
    func categories(budgetId: String, since: String?) async throws -> Page<WireCategory>

    func createExpense(_ expense: WireExpense) async throws -> WireExpense
    func updateExpense(_ expense: WireExpense) async throws
    @discardableResult func deleteExpense(id: Int64) async throws -> WireExpense

    func createCategory(_ category: WireCategory) async throws -> WireCategory
    func updateCategory(_ category: WireCategory) async throws
    @discardableResult func deleteCategory(id: Int64) async throws -> WireCategory
}

public protocol LocalStore: Sendable {
    func watermark(budgetId: String) async throws -> String?
    func setWatermark(_ watermark: String, budgetId: String) async throws
    func updateBudgetDetails(_ budget: WireBudget) async throws

    func pendingExpenses(budgetId: String) async throws -> [Pending<WireExpense>]
    func pendingCategories(budgetId: String) async throws -> [Pending<WireCategory>]

    func applyIncoming(_ expense: WireExpense) async throws
    func applyIncoming(_ category: WireCategory) async throws

    func replaceExpense(localId: Int64, with saved: WireExpense) async throws
    func replaceCategory(localId: Int64, with saved: WireCategory) async throws
    func markExpenseSynced(id: Int64) async throws
    func markCategorySynced(id: Int64) async throws
    func removeExpense(id: Int64) async throws
}
