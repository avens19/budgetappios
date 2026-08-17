import SwiftUI
import SwiftData
import BudgetCore

@main
struct WeeklyBudgetApp: App {

    private let container: ModelContainer
    @State private var session: BudgetSession

    init() {
        do {
            #if DEBUG
            // UI tests each want the same starting state, and one test's new
            // expense must not change the totals the next one asserts on.
            if CommandLine.arguments.contains("-resetStore") {
                container = try ModelContainer(
                    for: LocalBudget.self, LocalExpense.self, LocalCategory.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                DemoData.seedIfRequested(into: container.mainContext)
                _session = State(initialValue: BudgetSession(container: container))
                return
            }
            #endif
            container = try ModelContainer(
                for: LocalBudget.self, LocalExpense.self, LocalCategory.self)
        } catch {
            // Nothing here is worth recovering from: without a store the app
            // cannot do anything at all, and pretending otherwise would only
            // lose data later in a more confusing way.
            fatalError("Could not open the local store: \(error)")
        }
        #if DEBUG
        if DemoData.isRequested {
            DemoData.seed(into: container.mainContext)
            UserDefaults.standard.set(DemoData.budgetId, forKey: "budget.currentId")
        }
        if let joining = DemoData.budgetToJoin {
            DemoData.attach(to: joining, in: container.mainContext)
            UserDefaults.standard.set(joining, forKey: "budget.currentId")
        }
        #endif

        _session = State(initialValue: BudgetSession(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(BudgetSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    /// Deliberately a `@Query` rather than `session.currentBudget`.
    ///
    /// Sync runs on a `ModelActor` with its own context, and a budget fetched
    /// once from the main context does not pick up what that actor writes — the
    /// name and weekly amount stayed at whatever they were when the row was
    /// created, while the expenses (which come from their own `@Query`) updated
    /// around them. A query participates in the observation graph and re-reads.
    @Query private var budgets: [LocalBudget]

    private var current: LocalBudget? {
        guard let id = session.currentBudgetId else { return nil }
        return budgets.first { $0.uniqueId == id }
    }

    var body: some View {
        Group {
            if let budget = current {
                MainTabs(budget: budget)
            } else {
                OnboardingView()
            }
        }
        .task {
            #if DEBUG
            if let (detail, amount) = DemoData.expenseToAdd, let budget = current {
                session.addExpense(to: budget, date: BudgetCalendar.today(),
                                   detail: detail, amount: amount, categoryId: nil)
            }
            if let (category, detail, amount) = DemoData.pairToAdd, let budget = current {
                let created = session.addCategory(named: category, to: budget)
                session.addExpense(to: budget, date: BudgetCalendar.today(),
                                   detail: detail, amount: amount, categoryId: created.id)
            }
            #endif
            session.sync()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the app is exactly when another device's changes
            // are most likely to be waiting.
            if phase == .active { session.sync() }
        }
    }
}

/// Week, Month and Categories, matching the other two clients.
///
/// Adding an expense is a toolbar button and a sheet rather than a fourth tab:
/// a tab bar is for places, not actions, and a sheet is what iOS uses for a
/// short piece of data entry you finish and dismiss.
struct MainTabs: View {
    let budget: LocalBudget

    @State private var selection: Int

    init(budget: LocalBudget) {
        self.budget = budget
        #if DEBUG
        _selection = State(initialValue: DemoData.requestedTab)
        #else
        _selection = State(initialValue: 0)
        #endif
    }

    var body: some View {
        // `Tab { }` is iOS 18; `.tabItem` is the form that also works on 17,
        // and renders identically.
        TabView(selection: $selection) {
            NavigationStack { WeekView(budget: budget) }
                .tabItem { Label("Week", systemImage: "calendar.day.timeline.left") }
                .tag(0)

            NavigationStack { MonthView(budget: budget) }
                .tabItem { Label("Month", systemImage: "calendar") }
                .tag(1)

            NavigationStack { CategoriesView(budget: budget) }
                .tabItem { Label("Categories", systemImage: "chart.pie") }
                .tag(2)
        }
    }
}
