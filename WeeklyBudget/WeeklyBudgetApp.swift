import SwiftUI
import SwiftData
import BudgetCore

@main
struct WeeklyBudgetApp: App {

    private let container: ModelContainer
    @State private var session: BudgetSession

    init() {
        #if DEBUG
        // Density is read through @AppStorage, and a bare `-layout.dense 1` on the
        // command line does not reach it reliably — so the switch is explicit, like
        // -demo and -resetStore. Tests and screenshot runs need to pick a layout
        // without driving the settings sheet to get there.
        if CommandLine.arguments.contains("-dense") {
            UserDefaults.standard.set(true, forKey: Density.key)
        } else if CommandLine.arguments.contains("-roomy") {
            UserDefaults.standard.set(false, forKey: Density.key)
        }
        #endif

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

    /// What an invite link is doing, so the user is not left looking at a screen
    /// that has silently changed underneath them.
    @State private var inviteOutcome: InviteOutcome?
    @State private var redeeming = false

    private struct InviteOutcome: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

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
        // An invite link, arriving because the associated domain claims
        // /join/*. Redeeming here rather than on the server's page is the whole
        // point of the entitlement: the person never sees a browser.
        .onOpenURL { url in accept(url) }
        .overlay {
            if redeeming {
                // A modal wait, because the next thing that happens is the whole
                // screen changing to a different budget.
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Joining…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert(item: $inviteOutcome) { outcome in
            Alert(title: Text(outcome.title), message: Text(outcome.message),
                  dismissButton: .default(Text("OK")))
        }
    }

    private func accept(_ url: URL) {
        guard let token = inviteToken(in: url) else { return }
        redeeming = true
        Task {
            defer { redeeming = false }
            do {
                let budget = try await session.acceptInvite(token: token)
                let shared = budget.name.isEmpty ? String(localized: "this budget") : budget.name
                inviteOutcome = InviteOutcome(
                    title: String(localized: "Budget joined"),
                    message: String(localized: "You are now sharing \(shared). It will fill in as it syncs."))
            } catch let error as BudgetSession.InviteError {
                inviteOutcome = InviteOutcome(title: String(localized: "Invitation not valid"),
                                              message: error.errorDescription ?? "")
            } catch {
                inviteOutcome = InviteOutcome(
                    title: String(localized: "Could not join"),
                    message: String(localized: "Check your connection and open the link again."))
            }
        }
    }
}

/// `alert(item:)`, which SwiftUI never shipped.
///
/// The same trick as `sheet(item:)` — an Identifiable optional drives both the
/// presentation and the content, so there is no way to be showing an alert with
/// nothing to say in it.
private extension View {
    func alert<Item: Identifiable>(item: Binding<Item?>,
                                   content: @escaping (Item) -> Alert) -> some View {
        alert(isPresented: Binding(get: { item.wrappedValue != nil },
                                   set: { if !$0 { item.wrappedValue = nil } })) {
            content(item.wrappedValue!)
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
        // The identifiers are for the tests, and they are not decoration: on
        // iPad the tab bar is a control at the top of the window rather than a
        // bar at the bottom, and "Week" and "Month" are also the two options in
        // the Categories period picker. Without them a query by label is
        // ambiguous on exactly the screen where it matters.
        TabView(selection: $selection) {
            NavigationStack { WeekView(budget: budget) }
                .tabItem {
                    Label("Week", systemImage: "calendar.day.timeline.left")
                        .accessibilityIdentifier("tab.week")
                }
                .tag(0)

            NavigationStack { MonthView(budget: budget) }
                .tabItem {
                    Label("Month", systemImage: "calendar")
                        .accessibilityIdentifier("tab.month")
                }
                .tag(1)

            NavigationStack { CategoriesView(budget: budget) }
                .tabItem {
                    Label("Categories", systemImage: "chart.pie")
                        .accessibilityIdentifier("tab.categories")
                }
                .tag(2)
        }
    }
}
