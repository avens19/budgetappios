import Foundation

/// Which colour a category is drawn in.
///
/// Assigned by the category's rank in id order rather than by hashing the id.
/// This is the same rule `CategoryIndex` uses on Android and `categoryIndex()`
/// uses on the web, and it has to stay the same rule: a couple sharing a budget
/// across an iPhone and an Android phone should see Groceries as the same
/// colour on both, and a screenshot of one should be readable next to the other.
///
/// Hashing was tried first on Android and dropped. With ten colours and seven
/// categories a collision is more likely than not, and two identically coloured
/// slices in a pie chart defeat the point of colouring them at all. Ids are
/// handed out in ascending order by the server, so ranking means a new category
/// takes the next free colour and leaves the existing ones alone.
public struct CategoryPalette: Sendable {

    public static let count = 10

    private let slotById: [Int64: Int]
    private let nameById: [Int64: String]

    public init(categories: [WireCategory]) {
        let live = categories.filter { !$0.isDeleted }
        nameById = Dictionary(live.map { ($0.id, $0.name) }, uniquingKeysWith: { _, last in last })

        var slots: [Int64: Int] = [:]
        for (rank, id) in live.map(\.id).sorted().enumerated() {
            slots[id] = rank % Self.count
        }
        slotById = slots
    }

    /// `nil` for uncategorised, which is drawn in a neutral rather than given a
    /// slot in the palette — it should read as "not a category".
    ///
    /// An id left behind by a deleted category also lands here. The category is
    /// gone from the active list, so there is no name and no colour left for it.
    public func slot(for categoryId: Int64?) -> Int? {
        guard let categoryId else { return nil }
        return slotById[categoryId]
    }

    public func isKnown(_ categoryId: Int64?) -> Bool {
        guard let categoryId else { return false }
        return nameById[categoryId] != nil
    }

    public func name(for categoryId: Int64?, uncategorized: String = "Uncategorized") -> String {
        guard let categoryId, let name = nameById[categoryId] else { return uncategorized }
        return name
    }

    /// Groups spending the way the chart shows it, repeating the Android
    /// query exactly: system rows excluded, one bucket per category, only
    /// positive totals kept, biggest first.
    ///
    /// System rows are the carried balances, which are negative and generated
    /// rather than spent — charting them would make the ring disagree with the
    /// month. Ids whose category has been deleted fold into the uncategorised
    /// bucket, or the chart draws two slices both labelled "Uncategorized".
    public func breakdown(of expenses: [WireExpense]) -> [CategorySlice] {
        var totals: [Int64?: Double] = [:]
        for expense in expenses where !expense.isSystem {
            let key: Int64? = isKnown(expense.categoryId) ? expense.categoryId : nil
            totals[key, default: 0] += expense.amount
        }

        return totals
            .filter { $0.value > 0 }
            .map { CategorySlice(categoryId: $0.key, name: name(for: $0.key),
                                 slot: slot(for: $0.key), amount: $0.value) }
            .sorted {
                // Ties broken by name so the order cannot flicker between reloads.
                $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount
            }
    }
}

public struct CategorySlice: Sendable, Equatable, Identifiable {
    public let categoryId: Int64?
    public let name: String
    public let slot: Int?
    public let amount: Double

    public var id: Int64 { categoryId ?? -1 }

    public init(categoryId: Int64?, name: String, slot: Int?, amount: Double) {
        self.categoryId = categoryId
        self.name = name
        self.slot = slot
        self.amount = amount
    }
}
