import SwiftUI
import SwiftData
import BudgetCore

@main
struct WeeklyBudgetApp: App {

    private let container: ModelContainer
    @State private var session: BudgetSession

    init() {
        do {
            container = try ModelContainer(
                for: LocalBudget.self, LocalExpense.self, LocalCategory.self)
        } catch {
            // Nothing here is worth recovering from: without a store the app
            // cannot do anything at all, and pretending otherwise would only
            // lose data later in a more confusing way.
            fatalError("Could not open the local store: \(error)")
        }
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

    var body: some View {
        Group {
            if let budget = session.currentBudget {
                MainTabs(budget: budget)
            } else {
                OnboardingView()
            }
        }
        .task { session.sync() }
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

    var body: some View {
        TabView {
            Tab("Week", systemImage: "calendar.day.timeline.left") {
                NavigationStack { WeekView(budget: budget) }
            }
            Tab("Month", systemImage: "calendar") {
                NavigationStack { MonthView(budget: budget) }
            }
            Tab("Categories", systemImage: "chart.pie") {
                NavigationStack { CategoriesView(budget: budget) }
            }
        }
    }
}
