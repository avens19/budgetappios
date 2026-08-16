import SwiftUI
import BudgetCore

// MARK: - Colour

extension Color {
    /// The palette the other two clients use, value for value, so a category is
    /// the same colour on an iPhone, an Android phone and the web. Light and
    /// dark variants are in the asset catalog under Chart1…Chart10.
    static func chart(slot: Int?) -> Color {
        guard let slot else { return .secondary }
        return Color("Chart\((slot % CategoryPalette.count) + 1)")
    }
}

// MARK: - Formatting

enum Money {
    /// The device's own currency. The server stores a bare number and has no
    /// opinion, so the sensible thing is to show whatever the phone is set to
    /// rather than hard-coding dollars.
    static func string(_ value: Double) -> String {
        value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}

extension Date {
    /// Formatted in UTC on purpose: a budget day is a calendar day, and
    /// rendering it in the device's zone would show the 13th for a row that
    /// means the 14th.
    func budgetFormatted(_ format: Date.FormatStyle) -> String {
        format.timeZone(TimeZone(identifier: "UTC")!).format(self)
    }

    var dayHeading: String {
        budgetFormatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var shortDay: String {
        budgetFormatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Hero

/// The number the whole app exists to show: what is left this week.
struct HeroCard: View {
    let remaining: Double
    let spent: Double
    let limit: Double
    let onCarry: (() -> Void)?

    private var isOver: Bool { spent > limit }
    private var fraction: Double { limit <= 0 ? 0 : min(max(spent / limit, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isOver ? "Over budget" : "Left to spend")
                .font(.subheadline.weight(.medium))

            Text(Money.string(abs(remaining)))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            ProgressView(value: fraction)
                .tint(isOver ? Color(.systemRed) : .accentColor)

            HStack {
                Text("\(Money.string(spent)) of \(Money.string(limit))")
                    .font(.footnote)
                Spacer()
                if let onCarry {
                    Button("Carry balance", action: onCarry)
                        .font(.footnote.weight(.medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isOver ? Color(.systemRed).opacity(0.12) : Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(isOver ? Color(.systemRed) : Color.accentColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOver
            ? "Over budget by \(Money.string(abs(remaining)))"
            : "\(Money.string(abs(remaining))) left to spend, \(Money.string(spent)) of \(Money.string(limit))")
    }
}

// MARK: - Period stepper

/// ‹ label › — with the label itself tappable, because stepping a week at a
/// time is fine for last week and useless for last March.
struct PeriodStepper: View {
    let label: String
    let subtitle: String?
    let onBack: () -> Void
    let onForward: () -> Void
    let onTapLabel: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous")

            Spacer()

            Button(action: onTapLabel) {
                VStack(spacing: 2) {
                    Text(label).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Jump to a date")

            Spacer()

            Button(action: onForward) {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next")
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Expense row

struct ExpenseRow: View {
    let expense: LocalExpense
    let palette: CategoryPalette

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.chart(slot: palette.slot(for: expense.categoryId)))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.detail)
                    .lineLimit(1)
                Text(palette.name(for: expense.categoryId))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(Money.string(expense.amount))
                .monospacedDigit()
                .foregroundStyle(expense.amount < 0 ? Color.accentColor : .primary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}
