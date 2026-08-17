import Foundation
import SwiftData
import BudgetCore

/// Bridges the sync engine to SwiftData.
///
/// A `ModelActor`, so every mutation happens on one serialised context away
/// from the main thread. The engine is written against `LocalStore` and knows
/// nothing about SwiftData, which is what lets the whole protocol be tested
/// without a simulator.
@ModelActor
actor SwiftDataStore: LocalStore {

    // MARK: Budget

    func watermark(budgetId: String) throws -> String? {
        try budget(budgetId)?.watermark
    }

    func setWatermark(_ watermark: String, budgetId: String) throws {
        guard let budget = try budget(budgetId) else { return }
        budget.watermark = watermark
        try modelContext.save()
    }

    func updateBudgetDetails(_ wire: WireBudget) throws {
        guard let budget = try budget(wire.uniqueId) else { return }
        // Name, amount and start day are the server's to own — another device
        // may have changed them. The watermark is ours and is left alone.
        budget.name = wire.name
        budget.amount = wire.amount
        budget.startDay = wire.startDay
        try modelContext.save()
    }

    private func budget(_ id: String) throws -> LocalBudget? {
        try modelContext.fetch(
            FetchDescriptor<LocalBudget>(predicate: #Predicate { $0.uniqueId == id })
        ).first
    }

    // MARK: Pending work

    func pendingExpenses(budgetId: String) throws -> [Pending<WireExpense>] {
        let synced = SyncState.synced.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<LocalExpense>(
            predicate: #Predicate { $0.budgetId == budgetId && $0.stateRaw != synced },
            sortBy: [SortDescriptor(\.id)]))
        return rows.compactMap { row in
            guard let state = pendingState(row.state) else { return nil }
            return Pending(value: row.wire, state: state)
        }
    }

    func pendingCategories(budgetId: String) throws -> [Pending<WireCategory>] {
        let synced = SyncState.synced.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<LocalCategory>(
            predicate: #Predicate { $0.budgetId == budgetId && $0.stateRaw != synced },
            sortBy: [SortDescriptor(\.id)]))
        return rows.compactMap { row in
            guard let state = pendingState(row.state) else { return nil }
            return Pending(value: row.wire, state: state)
        }
    }

    private func pendingState(_ state: SyncState) -> PendingState? {
        switch state {
        case .synced: nil
        case .created: .created
        case .edited: .edited
        case .deleted: .deleted
        }
    }

    // MARK: Incoming

    func applyIncoming(_ wire: WireExpense) throws {
        let id = wire.id
        let existing = try modelContext.fetch(
            FetchDescriptor<LocalExpense>(predicate: #Predicate { $0.id == id })).first

        if wire.isDeleted {
            // The row is gone for good locally. It survives on the server so
            // that other devices hear about the deletion too.
            if let existing { modelContext.delete(existing) }
        } else if let existing {
            // A local edit that has not been pushed yet is newer than anything
            // the feed can be carrying, because the feed cannot know about it.
            // Overwriting here would silently discard what the user just typed.
            if existing.state == .synced {
                existing.apply(wire)
            }
        } else {
            modelContext.insert(LocalExpense(wire: wire, state: .synced))
        }
        try modelContext.save()
    }

    func applyIncoming(_ wire: WireCategory) throws {
        let id = wire.id
        let existing = try modelContext.fetch(
            FetchDescriptor<LocalCategory>(predicate: #Predicate { $0.id == id })).first

        if let existing {
            if existing.state == .synced {
                existing.name = wire.name
                existing.isDeleted = wire.isDeleted
            }
        } else {
            modelContext.insert(LocalCategory(id: wire.id, name: wire.name,
                                              budgetId: wire.budgetId,
                                              isDeleted: wire.isDeleted, state: .synced))
        }
        try modelContext.save()
    }

    // MARK: Push results

    func replaceExpense(localId: Int64, with saved: WireExpense) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<LocalExpense>(predicate: #Predicate { $0.id == localId })).first
        // The id changes from the local allocation to the server's, so the row
        // is replaced rather than edited: `id` is the unique attribute.
        if let existing { modelContext.delete(existing) }
        modelContext.insert(LocalExpense(wire: saved, state: .synced))
        try modelContext.save()
    }

    func replaceCategory(localId: Int64, with saved: WireCategory) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<LocalCategory>(predicate: #Predicate { $0.id == localId })).first
        if let existing { modelContext.delete(existing) }
        modelContext.insert(LocalCategory(id: saved.id, name: saved.name,
                                          budgetId: saved.budgetId,
                                          isDeleted: saved.isDeleted, state: .synced))

        // Expenses created against the local id have to follow it to the real
        // one. Without this they keep pointing at a category that no longer
        // exists here: the expense reads as "Uncategorized" on this device until
        // some later sync happens to overwrite it, and any edit pushes the dead
        // id back to the server. That is the bug that took down a client's whole
        // sync in production — the same shape, on the other side of the wire.
        let budgetId = saved.budgetId
        let affected = try modelContext.fetch(FetchDescriptor<LocalExpense>(
            predicate: #Predicate { $0.budgetId == budgetId }))
            .filter { $0.categoryId == localId }
        for expense in affected {
            expense.categoryId = saved.id
        }

        try modelContext.save()
    }

    func markExpenseSynced(id: Int64) throws {
        let row = try modelContext.fetch(
            FetchDescriptor<LocalExpense>(predicate: #Predicate { $0.id == id })).first
        row?.state = .synced
        try modelContext.save()
    }

    func markCategorySynced(id: Int64) throws {
        let row = try modelContext.fetch(
            FetchDescriptor<LocalCategory>(predicate: #Predicate { $0.id == id })).first
        row?.state = .synced
        try modelContext.save()
    }

    func removeExpense(id: Int64) throws {
        let row = try modelContext.fetch(
            FetchDescriptor<LocalExpense>(predicate: #Predicate { $0.id == id })).first
        if let row { modelContext.delete(row) }
        try modelContext.save()
    }
}
