import Foundation
import BudgetCore

/// Exercises the real client against a real server.
///
/// Creates a throwaway budget, drives every endpoint the app uses, runs a full
/// offline-then-sync round trip through the engine with an in-memory store, and
/// deletes the budget again. Nothing else is touched.
///
///     swift run BudgetCoreLive [base-url]
///
/// Separate from the unit suite because it needs the network and writes to a
/// live database, so it is not something to run in a loop.

let baseURL = CommandLine.arguments.count > 1
    ? URL(string: CommandLine.arguments[1])!
    : LiveAPIClient.productionURL

let api = LiveAPIClient(baseURL: baseURL)
let budgetId = UUID().uuidString.lowercased()
var failures: [String] = []

// Top-level code in an executable is main-actor isolated, so anything touching
// `failures` has to be too.
@MainActor
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    let mark = condition ? "ok  " : "FAIL"
    print("    \(mark) \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
    if !condition { failures.append(label) }
}

print("BudgetCore against \(baseURL.absoluteString)")
print("  budget \(budgetId)\n")

// MARK: - Budget

print("  budgets")
let created = try await api.createBudget(
    WireBudget(uniqueId: budgetId, name: "iOS live check", startDay: 0, amount: 300))
check("create returns the budget", created.uniqueId == budgetId)

let fetched = try await api.budget(id: budgetId)
check("read back", fetched?.name == "iOS live check", fetched?.name ?? "nil")
check("start day survives", fetched?.startDay == 0)
check("amount survives", fetched?.amount == 300)

let missing = try await api.budget(id: "definitely-not-a-budget")
check("unknown budget is nil, not an error", missing == nil)

// MARK: - Categories and expenses

print("\n  categories and expenses")
let groceries = try await api.createCategory(WireCategory(id: 0, name: "Groceries", budgetId: budgetId))
check("category created with a server id", groceries.id > 0, "id=\(groceries.id)")

let day = try WireDate.day(from: "2026-08-16")
let expense = try await api.createExpense(
    WireExpense(id: 0, date: day, description: "Big shop", amount: 84.20,
                budgetId: budgetId, categoryId: groceries.id))
check("expense created", expense.id > 0, "id=\(expense.id)")
check("date survives the round trip", expense.date == day, WireDate.string(from: expense.date))
check("amount survives", expense.amount == 84.20)
check("category attached", expense.categoryId == groceries.id)

var edited = expense
edited.amount = 90.00
try await api.updateExpense(edited)
let afterEdit = try await api.expenses(budgetId: budgetId, since: nil)
check("edit applied", afterEdit.items.first(where: { $0.id == expense.id })?.amount == 90.00)

// MARK: - Watermarks

print("\n  change feed")
let firstPage = try await api.expenses(budgetId: budgetId, since: nil)
check("watermark header present", firstPage.watermark != nil, firstPage.watermark ?? "absent")
if let mark = firstPage.watermark {
    check("watermark is fixed 28 characters", mark.count == 28, "\(mark.count)")
    // The client compares watermarks as strings; a variable width breaks that.
    let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$"#
    check("watermark shape", mark.range(of: pattern, options: .regularExpression) != nil)

    let empty = try await api.expenses(budgetId: budgetId, since: mark)
    check("replaying the watermark returns nothing", empty.items.isEmpty,
          "\(empty.items.count) rows")

    _ = try await api.createExpense(
        WireExpense(id: 0, date: day, description: "After the mark", amount: 5, budgetId: budgetId))
    let since = try await api.expenses(budgetId: budgetId, since: mark)
    check("a row written after the mark comes back", since.items.count == 1)
}

// MARK: - Soft delete

print("\n  deletion")
let deleted = try await api.deleteExpense(id: expense.id)
check("delete returns the row flagged deleted", deleted.isDeleted)
let feedAfterDelete = try await api.expenses(budgetId: budgetId, since: nil)
check("the deletion is carried in the feed",
      feedAfterDelete.items.contains { $0.id == expense.id && $0.isDeleted })

// MARK: - The engine, end to end

print("\n  sync engine against the live server")

/// The smallest store that behaves like the real one.
actor MemoryStore: LocalStore {
    var mark: String?
    var expenses: [Int64: WireExpense] = [:]
    var categories: [Int64: WireCategory] = [:]
    var pendingExpenseList: [Pending<WireExpense>] = []
    var pendingCategoryList: [Pending<WireCategory>] = []
    var budgetName = ""

    func queue(_ pending: Pending<WireExpense>) { pendingExpenseList.append(pending) }
    func clearPending() { pendingExpenseList = []; pendingCategoryList = [] }

    func watermark(budgetId: String) async throws -> String? { mark }
    func setWatermark(_ watermark: String, budgetId: String) async throws { mark = watermark }
    func updateBudgetDetails(_ budget: WireBudget) async throws { budgetName = budget.name }
    func pendingExpenses(budgetId: String) async throws -> [Pending<WireExpense>] { pendingExpenseList }
    func pendingCategories(budgetId: String) async throws -> [Pending<WireCategory>] { pendingCategoryList }
    func applyIncoming(_ expense: WireExpense) async throws {
        if expense.isDeleted { expenses[expense.id] = nil } else { expenses[expense.id] = expense }
    }
    func applyIncoming(_ category: WireCategory) async throws { categories[category.id] = category }
    func replaceExpense(localId: Int64, with saved: WireExpense) async throws {
        expenses[localId] = nil
        expenses[saved.id] = saved
        pendingExpenseList.removeAll { $0.value.id == localId }
    }
    func replaceCategory(localId: Int64, with saved: WireCategory) async throws {
        categories[localId] = nil
        categories[saved.id] = saved
        pendingCategoryList.removeAll { $0.value.id == localId }
    }
    func markExpenseSynced(id: Int64) async throws { pendingExpenseList.removeAll { $0.value.id == id } }
    func markCategorySynced(id: Int64) async throws { pendingCategoryList.removeAll { $0.value.id == id } }
    func removeExpense(id: Int64) async throws {
        expenses[id] = nil
        pendingExpenseList.removeAll { $0.value.id == id }
    }
}

let store = MemoryStore()
let engine = SyncEngine(api: api, store: store)

// First sync: everything on the server arrives, and the budget details land.
let first = try await engine.sync(budgetId: budgetId)
check("first sync pulls the server's rows", first.expensesPulled >= 1, "\(first.expensesPulled)")
check("first sync pulls categories", first.categoriesPulled >= 1, "\(first.categoriesPulled)")
check("budget details applied", await store.budgetName == "iOS live check")
check("watermark stored", await store.mark != nil)

// An expense created offline: a local id above the server's range, pushed on
// the next sync and replaced by the server's copy.
let offline = WireExpense(id: LocalIds.firstLocalId, date: day,
                          description: "Typed on the plane", amount: 12.34, budgetId: budgetId)
await store.queue(Pending(value: offline, state: .created))
_ = try await engine.sync(budgetId: budgetId)

let localStillThere = await store.expenses[LocalIds.firstLocalId]
check("the local id is gone after syncing", localStillThere == nil)
let serverSide = try await api.expenses(budgetId: budgetId, since: nil)
check("the offline expense reached the server",
      serverSide.items.contains { $0.description == "Typed on the plane" && !$0.isDeleted })

// A second sync with nothing pending must be a no-op, not a re-fetch.
let quiet = try await engine.sync(budgetId: budgetId)
check("an idle sync pulls nothing", quiet.expensesPulled == 0 && quiet.categoriesPulled == 0,
      "\(quiet.expensesPulled) expenses, \(quiet.categoriesPulled) categories")

// MARK: - Invites

// The unit suite covers these against a fake, which cannot catch the thing most
// likely to be wrong: the wire shape. `WireInvite` names six PascalCase keys and
// the server mints the link, so a renamed field or a changed path is a decode
// error at the one moment the app is asking someone to share their budget. The
// UI test deliberately does not tap "Create an invitation" — it would mint live
// invites on a real budget — which leaves this as the only place the round trip
// is actually exercised. It runs on the throwaway budget, so it is free to.
print("\n  invites")
let invite = try await api.createInvite(budgetId: budgetId)
check("invite created for this budget", invite.budgetId == budgetId, invite.budgetId)
check("with a token", !invite.token.isEmpty)
check("unused to begin with", invite.uses == 0 && invite.maxUses >= 1,
      "uses=\(invite.uses) max=\(invite.maxUses)")

// The cross-check worth having: the client's parser is deliberately narrow, and
// the server writes the URL. If those two ever disagree the link opens the app
// and then does nothing, which looks like the invitation being broken.
check("the server's link parses back to the same token",
      inviteToken(in: invite.url) == invite.token,
      "\(invite.url.path) -> \(inviteToken(in: invite.url) ?? "nil")")

let redeemed = try await api.redeemInvite(token: invite.token)
check("redeeming hands back the budget", redeemed?.uniqueId == budgetId,
      redeemed?.uniqueId ?? "nil")

if invite.maxUses == 1 {
    let second = try await api.redeemInvite(token: invite.token)
    check("a single-use invite is spent afterwards", second == nil,
          second == nil ? "" : "redeemed twice")
}

// Cancelling has to read as "no longer usable" rather than as an error, because
// that is the branch the app shows an explanation for.
let doomed = try await api.createInvite(budgetId: budgetId)
try await api.revokeInvite(token: doomed.token)
let afterRevoke = try await api.redeemInvite(token: doomed.token)
check("a cancelled invite redeems to nil, not an error", afterRevoke == nil,
      afterRevoke == nil ? "" : "still live")

let nonsense = try await api.redeemInvite(token: "aaaaaaaaaaaaaaaaaaaaaa")
check("an unknown token is nil too", nonsense == nil)

// MARK: - Cleanup

print("\n  cleanup")
var teardown = URLRequest(url: baseURL.appendingPathComponent("api/budget/\(budgetId)"))
teardown.httpMethod = "DELETE"
let (_, teardownResponse) = try await URLSession.shared.data(for: teardown)
let status = (teardownResponse as? HTTPURLResponse)?.statusCode ?? 0
check("test budget removed", status == 200, "HTTP \(status)")
check("and really gone", try await api.budget(id: budgetId) == nil)

print()
if failures.isEmpty {
    print("  all live checks passed")
    exit(0)
}
print("  \(failures.count) FAILED: \(failures.joined(separator: ", "))")
exit(1)
