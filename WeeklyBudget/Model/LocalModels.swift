import Foundation
import SwiftData
import BudgetCore

/// What is stored on the device.
///
/// The app is offline-first: every screen reads this store and never waits on
/// the network, and a sync reconciles it with the server afterwards. So each
/// row carries a `syncState` saying what the server still needs to be told.
///
/// Ids are the server's where the server has seen the row, and a local
/// allocation above `LocalIds.firstLocalId` where it has not. Keeping the
/// server's id is not optional: the change feed identifies rows by it, and
/// renumbering on arrival would detach the device from its own data.

enum SyncState: String, Codable, Sendable {
    case synced, created, edited, deleted
}

@Model
final class LocalBudget {
    @Attribute(.unique) var uniqueId: String
    var name: String
    var startDay: Int
    var amount: Double

    /// How far the change feeds have been consumed. Always the server's own
    /// answer, never this device's clock — see `SyncEngine.nextWatermark`.
    var watermark: String?

    /// When this budget was last opened, so "switch budget" can list the most
    /// recently used first.
    var lastOpened: Date

    init(uniqueId: String, name: String, startDay: Int, amount: Double,
         watermark: String? = nil, lastOpened: Date = .now) {
        self.uniqueId = uniqueId
        self.name = name
        self.startDay = startDay
        self.amount = amount
        self.watermark = watermark
        self.lastOpened = lastOpened
    }

    var calendar: BudgetCalendar { BudgetCalendar(startDay: startDay) }

    var wire: WireBudget {
        WireBudget(uniqueId: uniqueId, name: name, startDay: startDay, amount: amount)
    }
}

@Model
final class LocalExpense {
    @Attribute(.unique) var id: Int64
    var date: Date

    /// Not `description`: that name is taken on any class by
    /// `CustomStringConvertible`, and shadowing it makes debugging miserable.
    var detail: String
    var amount: Double
    var budgetId: String
    var categoryId: Int64?

    /// Generated rather than typed — the carried balance. Excluded from the
    /// category chart, because it is negative and would make the ring disagree
    /// with the total.
    var isSystem: Bool
    var stateRaw: String

    init(id: Int64, date: Date, detail: String, amount: Double, budgetId: String,
         categoryId: Int64? = nil, isSystem: Bool = false, state: SyncState = .created) {
        self.id = id
        self.date = date
        self.detail = detail
        self.amount = amount
        self.budgetId = budgetId
        self.categoryId = categoryId
        self.isSystem = isSystem
        self.stateRaw = state.rawValue
    }

    var state: SyncState {
        get { SyncState(rawValue: stateRaw) ?? .synced }
        set { stateRaw = newValue.rawValue }
    }

    var wire: WireExpense {
        WireExpense(id: id, date: date, description: detail, amount: amount,
                    budgetId: budgetId, categoryId: categoryId,
                    isDeleted: state == .deleted, isSystem: isSystem)
    }

    convenience init(wire: WireExpense, state: SyncState = .synced) {
        self.init(id: wire.id, date: wire.date, detail: wire.description, amount: wire.amount,
                  budgetId: wire.budgetId, categoryId: wire.categoryId,
                  isSystem: wire.isSystem, state: state)
    }

    func apply(_ wire: WireExpense) {
        date = wire.date
        detail = wire.description
        amount = wire.amount
        categoryId = wire.categoryId
        isSystem = wire.isSystem
    }
}

@Model
final class LocalCategory {
    @Attribute(.unique) var id: Int64
    var name: String
    var budgetId: String

    /// Soft delete, mirroring the server. The row survives so the change feed
    /// can tell other devices it went away, and so an expense still pointing at
    /// it does not dangle.
    var isDeleted: Bool
    var stateRaw: String

    init(id: Int64, name: String, budgetId: String,
         isDeleted: Bool = false, state: SyncState = .created) {
        self.id = id
        self.name = name
        self.budgetId = budgetId
        self.isDeleted = isDeleted
        self.stateRaw = state.rawValue
    }

    var state: SyncState {
        get { SyncState(rawValue: stateRaw) ?? .synced }
        set { stateRaw = newValue.rawValue }
    }

    var wire: WireCategory {
        WireCategory(id: id, name: name, budgetId: budgetId,
                     isDeleted: isDeleted || state == .deleted)
    }
}

// MARK: - Local ids

/// Hands out ids for rows created offline.
///
/// The counter starts at 10^12 and only ever goes up, matching the Android
/// client exactly. Server ids are a bigserial currently in the millions, so
/// there is no overlap — and a budget shared between an iPhone and an Android
/// phone must not have both devices minting the same id for different rows.
enum LocalIdSequence {
    private static let key = "budget.nextLocalId"

    static func next() -> Int64 {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: key) as? Int64
        let next = max(stored ?? LocalIds.firstLocalId, LocalIds.firstLocalId)
        defaults.set(next + 1, forKey: key)
        return next
    }
}
