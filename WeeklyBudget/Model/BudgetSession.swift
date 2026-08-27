import Foundation
import SwiftData
import SwiftUI
import BudgetCore

/// The current budget, and every mutation the UI can make.
///
/// Writes go to the local store first and return immediately — the app stays
/// usable on a train — then a sync is kicked off. Nothing in the UI ever waits
/// on the network.
@Observable
@MainActor
final class BudgetSession {

    private(set) var currentBudgetId: String?
    private(set) var isSyncing = false
    private(set) var lastSyncFailed = false

    private let container: ModelContainer
    private let api: any BudgetAPI
    private let invites: any InviteAPI

    /// Tokens this launch has already acted on.
    ///
    /// `onOpenURL` is not guaranteed to fire once per link — a relaunch that
    /// restores state can deliver the same URL again — and redeeming twice would
    /// spend the invite and then tell the user their brand-new budget could not
    /// be joined. Cheaper to remember than to reason about.
    private var handledTokens: Set<String> = []

    private static let currentKey = "budget.currentId"

    init(container: ModelContainer,
         api: any BudgetAPI = LiveAPIClient(),
         invites: any InviteAPI = LiveAPIClient()) {
        self.container = container
        self.api = api
        self.invites = invites
        self.currentBudgetId = UserDefaults.standard.string(forKey: Self.currentKey)
    }

    private var context: ModelContext { container.mainContext }

    // MARK: Current budget

    var currentBudget: LocalBudget? {
        guard let currentBudgetId else { return nil }
        return try? context.fetch(FetchDescriptor<LocalBudget>(
            predicate: #Predicate { $0.uniqueId == currentBudgetId })).first
    }

    func select(_ budget: LocalBudget) {
        budget.lastOpened = .now
        currentBudgetId = budget.uniqueId
        UserDefaults.standard.set(budget.uniqueId, forKey: Self.currentKey)
        try? context.save()
        sync()
    }

    /// Creates a budget here and on the server.
    ///
    /// The id is generated on the device, which is what makes a budget
    /// shareable: the same id typed into another device opens the same budget.
    @discardableResult
    func createBudget(name: String, amount: Double, startDay: Int) async throws -> LocalBudget {
        let wire = WireBudget(uniqueId: UUID().uuidString.lowercased(),
                              name: name, startDay: startDay, amount: amount)
        _ = try await api.createBudget(wire)

        let local = LocalBudget(uniqueId: wire.uniqueId, name: wire.name,
                                startDay: wire.startDay, amount: wire.amount)
        context.insert(local)
        try context.save()
        select(local)
        return local
    }

    /// Joins an existing budget by id.
    ///
    /// A 404 is the answer to a typo, so it is reported as such rather than
    /// leaving an empty budget lying around.
    @discardableResult
    func joinBudget(id rawId: String) async throws -> LocalBudget {
        let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let wire = try await api.budget(id: id) else { throw JoinError.notFound }

        if let existing = try context.fetch(FetchDescriptor<LocalBudget>(
            predicate: #Predicate { $0.uniqueId == id })).first {
            select(existing)
            return existing
        }

        let local = LocalBudget(uniqueId: wire.uniqueId, name: wire.name,
                                startDay: wire.startDay, amount: wire.amount)
        context.insert(local)
        try context.save()
        select(local)
        return local
    }

    enum JoinError: LocalizedError {
        case notFound
        var errorDescription: String? {
            String(localized: "No budget with that ID. Check it and try again.")
        }
    }

    // MARK: Invites

    func createInvite(for budget: LocalBudget) async throws -> WireInvite {
        try await invites.createInvite(budgetId: budget.uniqueId)
    }

    func revokeInvite(token: String) async throws {
        try await invites.revokeInvite(token: token)
    }

    /// Redeems an invite link and switches to the budget it stood for.
    ///
    /// There is no way to check first whether this device already has that
    /// budget: the token deliberately does not say which budget it points at
    /// until it is redeemed. So redeeming may spend a use to learn something the
    /// device already knew, which is the right trade — someone tapping a link
    /// they were sent expects it to be used up.
    @discardableResult
    func acceptInvite(token: String) async throws -> LocalBudget {
        if handledTokens.contains(token), let current = currentBudget { return current }
        handledTokens.insert(token)

        guard let wire = try await invites.redeemInvite(token: token) else {
            handledTokens.remove(token)
            throw InviteError.noLongerValid
        }

        let id = wire.uniqueId
        if let existing = try context.fetch(FetchDescriptor<LocalBudget>(
            predicate: #Predicate { $0.uniqueId == id })).first {
            // Already here — the link was used on a device that had it anyway.
            existing.name = wire.name
            existing.amount = wire.amount
            existing.startDay = wire.startDay
            try? context.save()
            select(existing)
            return existing
        }

        let local = LocalBudget(uniqueId: wire.uniqueId, name: wire.name,
                                startDay: wire.startDay, amount: wire.amount)
        context.insert(local)
        try context.save()
        select(local)
        return local
    }

    enum InviteError: LocalizedError {
        case noLongerValid
        var errorDescription: String? {
            String(localized: "That invitation has already been used, or it has expired. Ask for a new one.")
        }
    }

    func updateBudget(_ budget: LocalBudget, name: String, amount: Double, startDay: Int) {
        budget.name = name
        budget.amount = amount
        budget.startDay = startDay
        try? context.save()

        Task {
            try? await api.updateBudget(budget.wire)
            sync()
        }
    }

    /// Removes a budget from this device only. The server copy stays, so it can
    /// be joined again from the id and a partner's device is unaffected.
    func forget(_ budget: LocalBudget) {
        let id = budget.uniqueId
        try? context.delete(model: LocalExpense.self, where: #Predicate { $0.budgetId == id })
        try? context.delete(model: LocalCategory.self, where: #Predicate { $0.budgetId == id })
        context.delete(budget)
        try? context.save()

        if currentBudgetId == id {
            let next = try? context.fetch(FetchDescriptor<LocalBudget>(
                sortBy: [SortDescriptor(\.lastOpened, order: .reverse)])).first
            currentBudgetId = next?.uniqueId
            UserDefaults.standard.set(next?.uniqueId, forKey: Self.currentKey)
        }
    }

    // MARK: Expenses

    func addExpense(to budget: LocalBudget, date: Date, detail: String,
                    amount: Double, categoryId: Int64?, isSystem: Bool = false) {
        let expense = LocalExpense(id: LocalIdSequence.next(), date: date, detail: detail,
                                   amount: amount, budgetId: budget.uniqueId,
                                   categoryId: categoryId, isSystem: isSystem, state: .created)
        context.insert(expense)
        try? context.save()
        sync()
    }

    func updateExpense(_ expense: LocalExpense, date: Date, detail: String,
                       amount: Double, categoryId: Int64?) {
        expense.date = date
        expense.detail = detail
        expense.amount = amount
        expense.categoryId = categoryId
        // A row the server has never seen stays "created", or the push would
        // PUT an id that does not exist there yet.
        if expense.state == .synced { expense.state = .edited }
        try? context.save()
        sync()
    }

    func deleteExpense(_ expense: LocalExpense) {
        if expense.state == .created {
            // Never reached the server, so there is nothing to tell it.
            context.delete(expense)
        } else {
            expense.state = .deleted
        }
        try? context.save()
        sync()
    }

    /// The same expense, seven days on.
    func copyToNextWeek(_ expense: LocalExpense, in budget: LocalBudget) {
        let moved = budget.calendar.addingWeeks(1, to: expense.date)
        addExpense(to: budget, date: moved, detail: expense.detail,
                   amount: expense.amount, categoryId: expense.categoryId)
    }

    /// Moves what is left of a week into the next one.
    ///
    /// Written as a negative expense dated to the following week's first day,
    /// flagged as system. That is exactly what Android writes, and it raises
    /// next week's available spend without touching the budget amount.
    func carryBalance(_ remaining: Double, in budget: LocalBudget, weekStart: Date) {
        let rounded = (remaining * 100).rounded() / 100
        guard rounded >= 0.01 else { return }
        addExpense(to: budget,
                   date: budget.calendar.addingWeeks(1, to: weekStart),
                   detail: "Carried Balance", amount: -rounded,
                   categoryId: nil, isSystem: true)
    }

    // MARK: Categories

    @discardableResult
    func addCategory(named name: String, to budget: LocalBudget) -> LocalCategory {
        let category = LocalCategory(id: LocalIdSequence.next(), name: name,
                                     budgetId: budget.uniqueId, state: .created)
        context.insert(category)
        try? context.save()
        sync()
        return category
    }

    func rename(_ category: LocalCategory, to name: String) {
        category.name = name
        if category.state == .synced { category.state = .edited }
        try? context.save()
        sync()
    }

    /// Soft delete. The expenses in it stay and fall back to Uncategorized,
    /// which is what the server does and what the other clients show.
    func deleteCategory(_ category: LocalCategory) {
        if category.state == .created {
            context.delete(category)
        } else {
            category.isDeleted = true
            category.state = .deleted
        }
        try? context.save()
        sync()
    }

    // MARK: Sync

    func sync() {
        guard let budgetId = currentBudgetId, !isSyncing else { return }
        isSyncing = true

        Task { [container, api] in
            let store = SwiftDataStore(modelContainer: container)
            do {
                try await SyncEngine(api: api, store: store).sync(budgetId: budgetId)
                lastSyncFailed = false
            } catch {
                // Nothing is lost: local changes keep their pending state and
                // the next sync retries them. Offline is the normal case here,
                // not an error worth interrupting anyone over.
                lastSyncFailed = true
            }
            isSyncing = false
        }
    }

    /// Pull-to-refresh wants to hold the spinner until the work is done.
    func syncAndWait() async {
        guard let budgetId = currentBudgetId else { return }
        isSyncing = true
        let store = SwiftDataStore(modelContainer: container)
        do {
            try await SyncEngine(api: api, store: store).sync(budgetId: budgetId)
            lastSyncFailed = false
        } catch {
            lastSyncFailed = true
        }
        isSyncing = false
    }
}
