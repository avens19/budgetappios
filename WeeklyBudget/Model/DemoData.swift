#if DEBUG
import Foundation
import SwiftData
import BudgetCore

/// Seeds a budget with plausible data, for development and screenshots.
///
/// Debug builds only, and only when asked for explicitly:
///
///     WeeklyBudget -demo -tab categories
///
/// Everything it writes is marked `.synced` and the budget id is not a real
/// one, so nothing here ever tries to reach the server or push rows to it.
enum DemoData {

    static var isRequested: Bool { CommandLine.arguments.contains("-demo") }

    /// `-tab week|month|categories`, so each screen can be opened directly
    /// rather than tapped through.
    static var requestedTab: Int {
        guard let index = CommandLine.arguments.firstIndex(of: "-tab"),
              index + 1 < CommandLine.arguments.count else { return 0 }
        return switch CommandLine.arguments[index + 1] {
        case "month": 1
        case "categories": 2
        default: 0
        }
    }

    static let budgetId = "demo-0000-0000-0000-000000000000"

    /// `-join <budget-id>` attaches to a real budget on the server without
    /// tapping through onboarding, so a sync against a live server can be
    /// driven from the command line.
    static var budgetToJoin: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "-join"),
              index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    /// `-addExpense "Description:12.34"` writes one expense the way the UI
    /// does, so the push half of sync can be driven without tapping.
    static var expenseToAdd: (String, Double)? {
        guard let index = CommandLine.arguments.firstIndex(of: "-addExpense"),
              index + 1 < CommandLine.arguments.count else { return nil }
        let parts = CommandLine.arguments[index + 1].split(separator: ":")
        guard parts.count == 2, let amount = Double(parts[1]) else { return nil }
        return (String(parts[0]), amount)
    }

    /// Inserts only the budget row. Everything else arrives through the change
    /// feed on the first sync, which is the point of the exercise.
    static func attach(to id: String, in context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<LocalBudget>(
            predicate: #Predicate { $0.uniqueId == id })).first
        guard existing == nil else { return }
        context.insert(LocalBudget(uniqueId: id, name: "Joining…", startDay: 0, amount: 0))
        try? context.save()
    }

    static func seed(into context: ModelContext) {
        let id = budgetId
        let already = try? context.fetch(FetchDescriptor<LocalBudget>(
            predicate: #Predicate { $0.uniqueId == id })).first
        if already != nil { return }

        let budget = LocalBudget(uniqueId: id, name: "Household",
                                 startDay: 0, amount: 400)
        context.insert(budget)

        let names = ["Groceries", "Transport", "Eating out", "Fun"]
        var categoryIds: [String: Int64] = [:]
        for (index, name) in names.enumerated() {
            let categoryId = Int64(10 + index)
            categoryIds[name] = categoryId
            context.insert(LocalCategory(id: categoryId, name: name,
                                         budgetId: id, state: .synced))
        }

        let calendar = BudgetCalendar(startDay: 0)
        let weekStart = calendar.weekStart(containing: BudgetCalendar.today())
        func day(_ offset: Int) -> Date { WireDate.utc.date(byAdding: .day, value: offset, to: weekStart)! }

        // This week, spread across a few days so the day grouping shows.
        let thisWeek: [(Int, String, Double, String?)] = [
            (0, "Big shop", 84.20, "Groceries"),
            (0, "Coffee", 4.75, "Eating out"),
            (1, "Bus pass", 26.00, "Transport"),
            (1, "Corner shop", 12.60, "Groceries"),
            (2, "Curry night", 41.75, "Eating out"),
            (2, "Cinema", 22.00, "Fun"),
            (3, "Parking", 6.50, nil),
        ]

        var nextId: Int64 = 100
        for (offset, detail, amount, category) in thisWeek {
            context.insert(LocalExpense(id: nextId, date: day(offset), detail: detail,
                                        amount: amount, budgetId: id,
                                        categoryId: category.flatMap { categoryIds[$0] },
                                        state: .synced))
            nextId += 1
        }

        // Previous weeks, so the Month tab has something to roll up.
        for week in 1...4 {
            for (offset, detail, amount, category) in thisWeek.prefix(4) {
                let date = calendar.addingWeeks(-week, to: day(offset))
                context.insert(LocalExpense(
                    id: nextId, date: date, detail: detail,
                    amount: amount * (0.7 + Double(week % 3) * 0.2),
                    budgetId: id, categoryId: category.flatMap { categoryIds[$0] },
                    state: .synced))
                nextId += 1
            }
        }

        try? context.save()
    }
}
#endif
