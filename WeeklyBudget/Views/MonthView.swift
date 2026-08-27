import SwiftUI
import SwiftData
import BudgetCore

struct MonthView: View {
    @Environment(BudgetSession.self) private var session

    let budget: LocalBudget

    @State private var anchor = BudgetCalendar.today()
    @State private var showingDatePicker = false
    @State private var showingSettings = false

    @Query private var allExpenses: [LocalExpense]

    init(budget: LocalBudget) {
        self.budget = budget
        let id = budget.uniqueId
        _allExpenses = Query(filter: #Predicate<LocalExpense> { $0.budgetId == id },
                             sort: [SortDescriptor(\.date)])
    }

    private var calendar: BudgetCalendar { budget.calendar }

    private struct WeekSummary: Identifiable {
        let start: Date
        let total: Double
        var id: Date { start }
    }

    /// One row per budget week that begins in the month — the same span the
    /// other two clients add up, so the three never disagree about a total.
    private var weeks: [WeekSummary] {
        calendar.weeks(inMonthContaining: anchor).map { start in
            let end = calendar.addingWeeks(1, to: start)
            let total = allExpenses
                .filter { $0.state != .deleted && $0.date >= start && $0.date < end }
                .reduce(0) { $0 + $1.amount }
            return WeekSummary(start: start, total: total)
        }
    }

    /// Only what falls inside the calendar month itself, which is not the same
    /// as the sum of the weeks above — the first week usually starts in the
    /// previous month.
    private var monthTotal: Double {
        allExpenses
            .filter { $0.state != .deleted && calendar.isInMonth($0.date, monthContaining: anchor) }
            .reduce(0) { $0 + $1.amount }
    }

    private var isCurrentMonth: Bool {
        calendar.isInMonth(BudgetCalendar.today(), monthContaining: anchor)
    }

    private var monthLabel: String {
        let thisYear = WireDate.utc.component(.year, from: BudgetCalendar.today())
        let year = WireDate.utc.component(.year, from: anchor)
        return anchor.budgetFormatted(
            year == thisYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }

    var body: some View {
        List {
            Section {
                PeriodStepper(label: monthLabel, subtitle: nil,
                              onBack: { step(-1) },
                              onForward: { step(1) },
                              onTapLabel: { showingDatePicker = true })
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Spent this month").font(.subheadline.weight(.medium))
                    Text(Money.string(monthTotal))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("Weekly budget \(Money.string(budget.amount))")
                        .font(.footnote)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                .foregroundStyle(Color.accentColor)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
            }
            .listRowBackground(Color.clear)

            if weeks.allSatisfy({ $0.total == 0 }) {
                EmptyState(icon: "calendar",
                           title: "No expenses this month",
                           message: "Add expenses on the Week tab and they roll up here.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section("Weeks") {
                    ForEach(weeks) { week in
                        WeekSummaryRow(week: week, limit: budget.amount, calendar: calendar)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .readableContentWidth()
        .navigationTitle(budget.name.isEmpty ? "Weekly Budget" : budget.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await session.syncAndWait() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") { anchor = BudgetCalendar.today() }
                    .disabled(isCurrentMonth)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Budget settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { BudgetSettingsView(budget: budget) }
        }
        .sheet(isPresented: $showingDatePicker) {
            PeriodPickerSheet(title: "Jump to a month", selection: $anchor)
        }
    }

    private func step(_ direction: Int) {
        withAnimation(.snappy) { anchor = calendar.addingMonths(direction, to: anchor) }
    }

    private struct WeekSummaryRow: View {
        let week: WeekSummary
        let limit: Double
        let calendar: BudgetCalendar

        private var isOver: Bool { week.total > limit }
        private var fraction: Double { limit <= 0 ? 0 : min(max(week.total / limit, 0), 1) }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    let last = calendar.addingWeeks(1, to: week.start).addingTimeInterval(-86400)
                    Text("\(week.start.shortDay) – \(last.shortDay)")
                    Spacer()
                    Text(Money.string(week.total))
                        .monospacedDigit()
                        .foregroundStyle(isOver ? Color(.systemRed) : .primary)
                }
                ProgressView(value: fraction)
                    .tint(isOver ? Color(.systemRed) : .accentColor)
                Text(isOver
                     ? String(localized: "Over by \(Money.string(week.total - limit))")
                     : "\(Money.string(limit - week.total)) left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}
