import SwiftUI
import BudgetCore

/// The optional helper that works out a weekly number.
///
/// Every prompt can be left blank, the total moves as they are answered, and
/// the screen can be abandoned without touching the budget — which is also how
/// it works as a sanity check for someone who already has a figure in mind.
///
/// The arithmetic and the prompts live in `BudgetCore.WeeklyNumber`, shared with
/// the unit suite and matching the Android app and the website prompt for
/// prompt, so a number worked out on one client is reproducible on the others.
struct WeeklyNumberView: View {
    @Environment(\.dismiss) private var dismiss

    /// Where an accepted figure goes. The caller owns saving it: this screen is
    /// scratch paper, and the budget is written on the form that presented it.
    let onUse: (Double) -> Void

    @State private var amounts: [Int: String] = [:]
    @State private var periods: [Int: WeeklyNumber.Period] = [:]

    private var totals: (income: Double, outgoing: Double) {
        WeeklyNumber.totals(amounts: amounts, periods: periods)
    }

    private var weekly: Double {
        WeeklyNumber.weekly(income: totals.income, outgoing: totals.outgoing)
    }

    private var nothingEntered: Bool { totals.income == 0 && totals.outgoing == 0 }

    var body: some View {
        Form {
            Section {
                Text("Answer whichever of these you know. Anything left blank counts as nothing, and none of it reaches your budget until you tap Use this amount.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(WeeklyNumber.Group.allCases, id: \.self) { group in
                Section {
                    ForEach(WeeklyNumber.lines.filter { $0.group == group }) { line in
                        row(for: line)
                    }
                } header: {
                    Text(LocalizedStringKey(group.title))
                } footer: {
                    Text(LocalizedStringKey(group.help))
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Left to spend each week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Money.string(weekly))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Button("Use this amount") {
                    onUse((weekly * 100).rounded() / 100)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .disabled(weekly <= 0)
            }
        }
        .navigationTitle("Work out a weekly number")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func row(for line: WeeklyNumber.Line) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LocalizedStringKey(line.label))
                Spacer()
                TextField("0.00", text: binding(for: line))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
            }
            // A picker per row rather than one cycle for the whole form: pay
            // arrives fortnightly, rent monthly and insurance yearly, and
            // making everything monthly is exactly the approximation this
            // screen exists to avoid.
            Picker("How often", selection: periodBinding(for: line)) {
                ForEach(WeeklyNumber.Period.allCases, id: \.self) { period in
                    Text(LocalizedStringKey(period.label)).tag(period)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(LocalizedStringKey(line.label)))
    }

    private func binding(for line: WeeklyNumber.Line) -> Binding<String> {
        Binding(get: { amounts[line.id] ?? "" }, set: { amounts[line.id] = $0 })
    }

    private func periodBinding(for line: WeeklyNumber.Line) -> Binding<WeeklyNumber.Period> {
        Binding(get: { periods[line.id] ?? line.period }, set: { periods[line.id] = $0 })
    }

    /// Nothing entered yet is not a finding; more going out than coming in is,
    /// and it is the one this screen exists to surface.
    private var note: String {
        if nothingEntered {
            return String(localized: "Fill in what you can. The number updates as you type.")
        }
        if weekly <= 0 {
            return String(localized: "That leaves nothing to spend each week. Check the figures — or leave the steady spending out and track it here week to week instead.")
        }
        return String(localized: "\(Money.string(totals.income / WeeklyNumber.monthsPerYear)) a month in · \(Money.string(totals.outgoing / WeeklyNumber.monthsPerYear)) a month out")
    }
}
