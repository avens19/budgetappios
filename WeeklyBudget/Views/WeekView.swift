import SwiftUI
import SwiftData
import BudgetCore

struct WeekView: View {
    @Environment(BudgetSession.self) private var session
    @Environment(\.modelContext) private var context

    let budget: LocalBudget

    @State private var anchor = BudgetCalendar.today()
    @State private var confirmingCarry = false

    @AppStorage(Density.key) private var dense = false

    /// One sheet, not four.
    ///
    /// Stacking several `.sheet` modifiers on the same view does not reliably
    /// work: with four of them here, tapping a row set the state but nothing
    /// was ever presented, so expenses could not be opened for editing at all.
    /// A single modifier driven by an enum is the supported shape.
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case add
        case edit(LocalExpense)
        case settings
        case datePicker

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let expense): "edit-\(expense.id)"
            case .settings: "settings"
            case .datePicker: "datePicker"
            }
        }
    }

    @Query private var allExpenses: [LocalExpense]
    @Query private var allCategories: [LocalCategory]

    init(budget: LocalBudget) {
        self.budget = budget
        let id = budget.uniqueId
        _allExpenses = Query(filter: #Predicate<LocalExpense> { $0.budgetId == id },
                             sort: [SortDescriptor(\.date), SortDescriptor(\.id)])
        _allCategories = Query(filter: #Predicate<LocalCategory> { $0.budgetId == id })
    }

    private var calendar: BudgetCalendar { budget.calendar }
    private var weekStart: Date { calendar.weekStart(containing: anchor) }
    private var weekEnd: Date { calendar.weekEnd(containing: anchor) }

    private var expenses: [LocalExpense] {
        // `.deleted` is a row awaiting a DELETE on the server, not a row the
        // user should still be looking at.
        allExpenses.filter { $0.state != .deleted && $0.date >= weekStart && $0.date < weekEnd }
    }

    private var palette: CategoryPalette {
        CategoryPalette(categories: allCategories.map(\.wire))
    }

    private var spent: Double { expenses.reduce(0) { $0 + $1.amount } }
    private var remaining: Double { budget.amount - spent }

    private var isCurrentWeek: Bool {
        let today = BudgetCalendar.today()
        return today >= weekStart && today < weekEnd
    }

    private var subtitle: String? {
        guard isCurrentWeek else { return nil }
        let left = calendar.daysLeftInWeek(from: BudgetCalendar.today())
        // String(localized:) rather than a bare literal: this is a String the
        // view is handed, so nothing else would look it up.
        return switch left {
        case 0: String(localized: "This week · Last day")
        case 1: String(localized: "This week · 1 day left")
        default: String(localized: "This week · \(left) days left")
        }
    }

    /// Expenses grouped under a heading per day, as on the other clients.
    private var days: [(date: Date, total: Double, rows: [LocalExpense])] {
        Dictionary(grouping: expenses, by: \.date)
            .map { (date: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }, rows: $0.value) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        List {
            Section {
                PeriodStepper(
                    label: "\(weekStart.shortDay) – \(calendar.addingWeeks(1, to: weekStart).addingTimeInterval(-86400).shortDay)",
                    subtitle: subtitle,
                    onBack: { step(-1) },
                    onForward: { step(1) },
                    onTapLabel: { sheet = .datePicker })
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                HeroCard(remaining: remaining, spent: spent, limit: budget.amount,
                         onCarry: remaining >= 0.01 ? { confirmingCarry = true } : nil,
                         dense: dense)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: dense ? 8 : 16,
                                              bottom: dense ? 6 : 12, trailing: dense ? 8 : 16))
            }
            .listRowBackground(Color.clear)

            if expenses.isEmpty {
                Section {
                    EmptyState(icon: "tray",
                               title: "Nothing spent yet",
                               message: "Expenses you add for this week will show up here.")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if dense {
                // One running list in date order, deliberately: several long-time
                // users treat the week that way and do not always file an expense
                // under the right day.
                Section {
                    ForEach(expenses) { expense in
                        row(for: expense)
                    }
                    if !expenses.isEmpty {
                        WeekTotalRow(spent: spent, limit: budget.amount)
                    }
                }
            } else {
                ForEach(days, id: \.date) { day in
                    Section {
                        ForEach(day.rows) { expense in
                            row(for: expense)
                        }
                    } header: {
                        HStack {
                            Text(day.date.dayHeading)
                            Spacer()
                            Text(Money.string(day.total)).monospacedDigit()
                        }
                    }
                }
            }
        }
        .densityListStyle(dense: dense)
        .readableContentWidth()
        .navigationTitle(budget.name.isEmpty ? "Weekly Budget" : budget.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await session.syncAndWait() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") { anchor = BudgetCalendar.today() }
                    .disabled(isCurrentWeek)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { sheet = .settings } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Budget settings")
                .accessibilityIdentifier("budgetSettings")

                Button { sheet = .add } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add expense")
                .accessibilityIdentifier("addExpense")
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .add:
                ExpenseEditor(budget: budget, expense: nil, defaultDate: defaultDateForNewExpense)
            case .edit(let expense):
                ExpenseEditor(budget: budget, expense: expense, defaultDate: expense.date)
            case .settings:
                NavigationStack { BudgetSettingsView(budget: budget) }
            case .datePicker:
                PeriodPickerSheet(title: "Jump to a week", selection: $anchor)
            }
        }
        .confirmationDialog("Carry balance", isPresented: $confirmingCarry, titleVisibility: .visible) {
            Button("Move \(Money.string(remaining)) to next week") {
                session.carryBalance(remaining, in: budget, weekStart: weekStart)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Next week's spending goes up by \(Money.string(remaining)).")
        }
    }

    /// One row, whichever layout is showing: the density changes how a row looks,
    /// never what it can do. Written once so the swipe and the context menu cannot
    /// go missing from one of them.
    @ViewBuilder
    private func row(for expense: LocalExpense) -> some View {
        Button { sheet = .edit(expense) } label: {
            ExpenseRow(expense: expense, palette: palette, dense: dense)
        }
        .buttonStyle(.plain)
        // Swipe to delete is what an iOS user reaches for first; the context menu
        // carries the rarer actions.
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                session.deleteExpense(expense)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                session.copyToNextWeek(expense, in: budget)
            } label: {
                Label("Copy to next week", systemImage: "calendar.badge.plus")
            }
            Button(role: .destructive) {
                session.deleteExpense(expense)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Adding from a week you are looking at should default to that week, not
    /// to today — but if you are on the current week, today is the right guess.
    private var defaultDateForNewExpense: Date {
        isCurrentWeek ? BudgetCalendar.today() : weekStart
    }

    private func step(_ direction: Int) {
        withAnimation(.snappy) {
            anchor = calendar.addingWeeks(direction, to: weekStart)
        }
    }
}

/// A date picker in a sheet, sized to its content.
struct PeriodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    @Binding var selection: Date

    /// The picker works in the device's zone; budget dates are UTC days. These
    /// convert across so the day the user taps is the day that gets stored.
    @State private var localSelection = Date()

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $localSelection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            selection = BudgetCalendar.today(now: localSelection)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            var local = Calendar(identifier: .gregorian)
            local.timeZone = .current
            let parts = WireDate.utc.dateComponents([.year, .month, .day], from: selection)
            localSelection = local.date(from: parts) ?? Date()
        }
    }
}
