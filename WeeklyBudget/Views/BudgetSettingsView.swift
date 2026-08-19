import SwiftUI
import SwiftData
import BudgetCore

/// Budget settings, switching budgets, sharing the id, and the explanation —
/// the equivalent of Android's overflow menu, gathered into one sheet.
struct BudgetSettingsView: View {
    @Environment(BudgetSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let budget: LocalBudget

    @State private var name = ""
    @State private var amount = ""
    @State private var startDay = 0
    @State private var copied = false
    @State private var confirmingForget = false

    @Query(sort: [SortDescriptor(\LocalBudget.lastOpened, order: .reverse)])
    private var budgets: [LocalBudget]

    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday",
                                   "Thursday", "Friday", "Saturday"]

    /// Built from the API host rather than written out again, so a move takes
    /// the link with it.
    private static let appsPage = LiveAPIClient.productionURL.appending(path: "Apps")

    private var parsedAmount: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        Form {
            Section("Budget") {
                TextField("Name", text: $name)
                HStack {
                    Text("Weekly amount")
                    Spacer()
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                Picker("Week starts on", selection: $startDay) {
                    ForEach(0..<7, id: \.self) { Text(Self.weekdays[$0]).tag($0) }
                }
            }

            Section {
                // Tap to copy: the id is the whole sharing mechanism, and
                // nobody is going to retype a UUID accurately.
                Button {
                    UIPasteboard.general.string = budget.uniqueId
                    withAnimation { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Budget ID").font(.caption).foregroundStyle(.secondary)
                            Text(budget.uniqueId)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .foregroundStyle(copied ? Color.green : Color.accentColor)
                    }
                }
                .buttonStyle(.plain)

                ShareLink(item: budget.uniqueId) {
                    Label("Share budget ID", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Enter this ID on another device — another phone, or the web app — to use the same budget.")
            }

            if budgets.count > 1 {
                Section("Switch budget") {
                    ForEach(budgets.filter { $0.uniqueId != budget.uniqueId }) { other in
                        Button {
                            session.select(other)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(other.name.isEmpty ? "Untitled" : other.name)
                                        .foregroundStyle(.primary)
                                    Text(Money.string(other.amount) + " a week")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink { AddBudgetView() } label: {
                    Label("Add another budget", systemImage: "plus")
                }
                NavigationLink { HowItWorksView() } label: {
                    Label("How this works", systemImage: "questionmark.circle")
                }
                // A page on the web app, not a store link, and the reason is
                // App Store guideline 2.3.10: an app may not name or picture
                // other mobile platforms. That page can say plainly what runs
                // on what, and it is where the Android app points too, so
                // neither build has to mention the other.
                Link(destination: Self.appsPage) {
                    Label("Apps for other devices", systemImage: "arrow.up.forward.app")
                }
            }

            Section {
                Button(role: .destructive) { confirmingForget = true } label: {
                    Text("Remove from this device")
                }
            } footer: {
                Text("The budget itself is not deleted. Anyone else using it keeps it, and you can join again with the ID.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { saveIfChanged(); dismiss() }
            }
        }
        .confirmationDialog("Remove this budget from the device?",
                            isPresented: $confirmingForget, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                session.forget(budget)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            name = budget.name
            amount = String(format: "%g", budget.amount)
            startDay = budget.startDay
        }
    }

    private func saveIfChanged() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let value = parsedAmount else { return }
        guard trimmed != budget.name || value != budget.amount || startDay != budget.startDay
        else { return }
        session.updateBudget(budget, name: trimmed, amount: value, startDay: startDay)
    }
}

/// Create another budget from inside the app, once one already exists.
struct AddBudgetView: View {
    @Environment(BudgetSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amount = ""
    @State private var startDay = 0
    @State private var joinId = ""
    @State private var busy = false
    @State private var error: String?

    private var parsedAmount: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        Form {
            Section("New budget") {
                TextField("Name", text: $name)
                TextField("Weekly amount", text: $amount).keyboardType(.decimalPad)
                Picker("Week starts on", selection: $startDay) {
                    ForEach(0..<7, id: \.self) {
                        Text(["Sunday", "Monday", "Tuesday", "Wednesday",
                              "Thursday", "Friday", "Saturday"][$0]).tag($0)
                    }
                }
                Button("Create") { create() }
                    .disabled(busy || parsedAmount == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Or join one") {
                TextField("Budget ID", text: $joinId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                Button("Join") { join() }
                    .disabled(busy || joinId.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error {
                Section { Text(error).foregroundStyle(Color(.systemRed)) }
            }
        }
        .navigationTitle("Add budget")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create() {
        busy = true
        Task {
            do {
                try await session.createBudget(name: name.trimmingCharacters(in: .whitespaces),
                                               amount: parsedAmount ?? 0, startDay: startDay)
                dismiss()
            } catch {
                self.error = "Could not create that budget. Check your connection and try again."
            }
            busy = false
        }
    }

    private func join() {
        busy = true
        Task {
            do {
                try await session.joinBudget(id: joinId)
                dismiss()
            } catch let joinError as BudgetSession.JoinError {
                error = joinError.errorDescription
            } catch {
                self.error = "Could not reach the server. Check your connection and try again."
            }
            busy = false
        }
    }
}
