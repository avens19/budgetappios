import SwiftUI
import SwiftData
import Charts
import BudgetCore

struct CategoriesView: View {
    @Environment(BudgetSession.self) private var session

    let budget: LocalBudget

    enum Period: String, CaseIterable {
        case week = "Week", month = "Month"

        /// The raw value is the segment's identity; this is what it says. A
        /// picker built on rawValue shows English in every language.
        var label: LocalizedStringKey { LocalizedStringKey(rawValue) }
    }

    @State private var period: Period = .week
    @State private var anchor = BudgetCalendar.today()
    @State private var selected: Int64??
    @State private var showingDatePicker = false
    @State private var managing = false

    @Query private var allExpenses: [LocalExpense]
    @Query private var allCategories: [LocalCategory]

    init(budget: LocalBudget) {
        self.budget = budget
        let id = budget.uniqueId
        _allExpenses = Query(filter: #Predicate<LocalExpense> { $0.budgetId == id },
                             sort: [SortDescriptor(\.date)])
        _allCategories = Query(filter: #Predicate<LocalCategory> { $0.budgetId == id })
    }

    private var calendar: BudgetCalendar { budget.calendar }
    private var liveCategories: [LocalCategory] {
        allCategories.filter { !$0.isDeleted }.sorted { $0.name < $1.name }
    }
    private var palette: CategoryPalette {
        CategoryPalette(categories: allCategories.map(\.wire))
    }

    private var range: (start: Date, end: Date) {
        switch period {
        case .week:
            (calendar.weekStart(containing: anchor), calendar.weekEnd(containing: anchor))
        case .month:
            (calendar.monthStart(containing: anchor),
             calendar.addingMonths(1, to: anchor))
        }
    }

    private var expensesInPeriod: [LocalExpense] {
        allExpenses.filter { $0.state != .deleted && $0.date >= range.start && $0.date < range.end }
    }

    private var slices: [CategorySlice] {
        palette.breakdown(of: expensesInPeriod.map(\.wire))
    }

    private var total: Double { slices.reduce(0) { $0 + $1.amount } }

    private var periodLabel: String {
        switch period {
        case .week:
            let start = calendar.weekStart(containing: anchor)
            let last = calendar.addingWeeks(1, to: start).addingTimeInterval(-86400)
            return "\(start.shortDay) – \(last.shortDay)"
        case .month:
            let thisYear = WireDate.utc.component(.year, from: BudgetCalendar.today())
            let year = WireDate.utc.component(.year, from: anchor)
            return anchor.budgetFormatted(
                year == thisYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
        }
    }

    private var isCurrentPeriod: Bool {
        let today = BudgetCalendar.today()
        return today >= range.start && today < range.end
    }

    /// The expenses behind whichever slice is selected, so a surprising total
    /// can be traced back to the things that made it.
    private var selectedExpenses: [LocalExpense] {
        guard let selected else { return [] }
        return expensesInPeriod
            .filter { !$0.isSystem }
            .filter { (palette.isKnown($0.categoryId) ? $0.categoryId : nil) == selected }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $period.animation(.snappy)) {
                    ForEach(Period.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                PeriodStepper(label: periodLabel, subtitle: nil,
                              onBack: { step(-1) }, onForward: { step(1) },
                              onTapLabel: { showingDatePicker = true })
                    .listRowSeparator(.hidden)
            }
            .listRowBackground(Color.clear)

            if slices.isEmpty {
                EmptyState(icon: "chart.pie",
                           title: "Nothing to chart yet",
                           message: "Once you tag expenses with a category, the breakdown appears here.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    donut
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(slices) { slice in
                        Button {
                            withAnimation(.snappy) {
                                selected = (selected == slice.categoryId) ? nil : slice.categoryId
                            }
                        } label: {
                            LegendRow(slice: slice, total: total,
                                      isSelected: selected == slice.categoryId)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Tap a category to see its expenses.")
                }

                if let selected, !selectedExpenses.isEmpty {
                    Section(palette.name(for: selected)) {
                        ForEach(selectedExpenses) { expense in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(expense.detail)
                                    Text(expense.date.shortDay)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.string(expense.amount)).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .readableContentWidth()
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await session.syncAndWait() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") { anchor = BudgetCalendar.today() }
                    .disabled(isCurrentPeriod)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Manage") { managing = true }
                    .disabled(liveCategories.isEmpty)
            }
        }
        .sheet(isPresented: $managing) {
            NavigationStack { ManageCategoriesView(budget: budget) }
        }
        .sheet(isPresented: $showingDatePicker) {
            PeriodPickerSheet(title: period == .week ? "Jump to a week" : "Jump to a month",
                              selection: $anchor)
        }
    }

    private var donut: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Amount", slice.amount),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(Color.chart(slot: slice.slot))
            // Dimming rather than hiding keeps the ring the same size, so
            // selecting a slice does not make the chart jump.
            .opacity(selected == nil || selected == slice.categoryId ? 1 : 0.25)
        }
        .chartLegend(.hidden)
        .frame(height: 240)
        .overlay {
            VStack(spacing: 2) {
                Text(Money.string(total))
                    .font(.title2.weight(.semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(period == .week ? "this week" : "this month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 48)
        }
        .accessibilityLabel("Spending by category")
        .accessibilityValue(slices.map { "\($0.name) \(Money.string($0.amount))" }
            .joined(separator: ", "))
    }

    private func step(_ direction: Int) {
        withAnimation(.snappy) {
            anchor = period == .week
                ? calendar.addingWeeks(direction, to: calendar.weekStart(containing: anchor))
                : calendar.addingMonths(direction, to: anchor)
            selected = nil
        }
    }

    private struct LegendRow: View {
        let slice: CategorySlice
        let total: Double
        let isSelected: Bool

        var body: some View {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.chart(slot: slice.slot))
                    .frame(width: 14, height: 14)
                Text(slice.name).lineLimit(1)
                Spacer(minLength: 8)
                // verbatim: a number and a percent sign, with no words in it.
                // Left as a localizable literal it becomes a catalog key that
                // twenty translators would be asked to leave alone.
                Text(verbatim: "\(Int((slice.amount / max(total, 0.01) * 100).rounded()))%")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text(Money.string(slice.amount)).monospacedDigit()
            }
            .contentShape(Rectangle())
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : nil)
        }
    }
}

/// Renaming and deleting, kept on its own screen because both are rare and one
/// is destructive.
struct ManageCategoriesView: View {
    @Environment(BudgetSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let budget: LocalBudget

    @Query private var categories: [LocalCategory]
    @State private var renaming: LocalCategory?
    @State private var newName = ""

    init(budget: LocalBudget) {
        self.budget = budget
        let id = budget.uniqueId
        _categories = Query(filter: #Predicate<LocalCategory> { $0.budgetId == id },
                            sort: [SortDescriptor(\.name)])
    }

    private var live: [LocalCategory] { categories.filter { !$0.isDeleted } }

    var body: some View {
        List {
            if live.isEmpty {
                EmptyState(icon: "tag",
                           title: "No categories yet",
                           message: "Create one while adding an expense and it will appear here.")
                    .listRowBackground(Color.clear)
            }
            ForEach(live) { category in
                Text(category.name)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            session.deleteCategory(category)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            newName = category.name
                            renaming = category
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.accentColor)
                    }
            }
        }
        .navigationTitle("Manage categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .alert("Rename category", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    session.rename(renaming, to: newName.trimmingCharacters(in: .whitespaces))
                }
                renaming = nil
            }
        } message: {
            Text("Expenses keep their category.")
        }
    }
}
