import SwiftUI
import BudgetCore

/// First run: the four tutorial pages, then create or join.
///
/// The copy is the Android app's, word for word. The point of it is to say what
/// the app is deliberately *not* for — no fixed bills, income as a negative —
/// and three clients explaining that differently would be worse than one
/// explaining it once.
struct OnboardingView: View {
    @State private var page = 0
    @State private var showingSetup = false

    private struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: [String]
    }

    private let pages: [Page] = [
        Page(symbol: "dollarsign.circle.fill",
             title: "Budget your spending money",
             body: ["Start outside the app. Take what you earn, subtract the bills that never change — rent, insurance, subscriptions, loan payments — and whatever is left is your spending money.",
                    "Split that across the weeks in the month, and you have your weekly target."]),
        Page(symbol: "doc.text.fill",
             title: "Bills don't belong in here",
             body: ["There is deliberately nowhere to enter recurring income or expenses. Those amounts are already fixed, so leaving them out keeps the app focused on the one number that actually moves: what you spent this week.",
                    "If money comes in mid-week — a refund, a gift, cash back — add it as an expense with a minus sign."]),
        Page(symbol: "person.2.fill",
             title: "Share it with your partner",
             body: ["One budget can live on as many devices as you like, and they all stay in step.",
                    "Open Settings, copy the budget ID, and enter it on the other device. You will both see the same running total."]),
        Page(symbol: "iphone.and.arrow.forward",
             title: "It works with the others",
             body: ["The same budget opens on other phones and at budget.andrewovens.com, with the same expenses and the same total.",
                    "Add an expense on any of them and the rest catch up within seconds."]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: item.symbol)
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                            .padding(24)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 28))

                        Text(item.title)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)

                        ForEach(item.body, id: \.self) { paragraph in
                            Text(paragraph)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            HStack {
                Button("Skip") { showingSetup = true }
                    .opacity(page == pages.count - 1 ? 0 : 1)
                Spacer()
                Button(page == pages.count - 1 ? "Get started" : "Next") {
                    withAnimation {
                        if page == pages.count - 1 { showingSetup = true } else { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showingSetup) {
            NavigationStack { FirstBudgetView() }
                .interactiveDismissDisabled()
        }
    }
}

/// The first budget: create one, or join one that already exists.
struct FirstBudgetView: View {
    @Environment(BudgetSession.self) private var session

    @State private var mode = Mode.create
    @State private var name = ""
    @State private var amount = ""
    @State private var startDay = 0
    @State private var joinId = ""
    @State private var busy = false
    @State private var error: String?

    enum Mode: String, CaseIterable { case create = "Create", join = "Join" }

    private var parsedAmount: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        Form {
            Section {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            switch mode {
            case .create:
                Section {
                    TextField("Name, e.g. Household", text: $name)
                    HStack {
                        Text("Weekly amount")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    Picker("Week starts on", selection: $startDay) {
                        ForEach(0..<7, id: \.self) {
                            Text(["Sunday", "Monday", "Tuesday", "Wednesday",
                                  "Thursday", "Friday", "Saturday"][$0]).tag($0)
                        }
                    }
                } footer: {
                    Text("What you can spend in a week, after the bills that never change.")
                }

            case .join:
                Section {
                    TextField("Budget ID", text: $joinId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                } footer: {
                    Text("Copy the ID from Settings on the device that already has the budget.")
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(Color(.systemRed)) }
            }

            Section {
                Button(mode == .create ? "Create budget" : "Join budget") { submit() }
                    .frame(maxWidth: .infinity)
                    .disabled(busy || !canSubmit)
            }
        }
        .navigationTitle(mode == .create ? "New budget" : "Join a budget")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if busy { ProgressView().controlSize(.large) }
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .create:
            parsedAmount != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .join:
            !joinId.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                switch mode {
                case .create:
                    try await session.createBudget(
                        name: name.trimmingCharacters(in: .whitespaces),
                        amount: parsedAmount ?? 0, startDay: startDay)
                case .join:
                    try await session.joinBudget(id: joinId)
                }
            } catch let joinError as BudgetSession.JoinError {
                error = joinError.errorDescription
            } catch {
                self.error = "Could not reach the server. Check your connection and try again."
            }
            busy = false
        }
    }
}

/// The tutorial again, reachable from Settings.
struct HowItWorksView: View {
    private struct Item: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let items: [Item] = [
        Item(symbol: "dollarsign.circle.fill", title: "Budget your spending money",
             body: "Take what you earn, subtract the bills that never change — rent, insurance, subscriptions, loan payments — and whatever is left is your spending money. Split that across the weeks in the month, and you have your weekly target."),
        Item(symbol: "doc.text.fill", title: "Bills don't belong in here",
             body: "There is deliberately nowhere to enter recurring income or expenses. Those amounts are already fixed, so leaving them out keeps the app focused on the one number that actually moves: what you spent this week.\n\nIf money comes in mid-week — a refund, a gift, cash back — add it as an expense with a minus sign."),
        Item(symbol: "person.2.fill", title: "Share it with your partner",
             body: "One budget can live on as many devices as you like, and they all stay in step. Copy the budget ID from Settings and enter it on the other device."),
        Item(symbol: "iphone.and.arrow.forward", title: "It works with the others",
             body: "The same budget opens on other phones and at budget.andrewovens.com, with the same expenses and the same total."),
    ]

    var body: some View {
        List(items) { item in
            VStack(alignment: .leading, spacing: 8) {
                Label(item.title, systemImage: item.symbol)
                    .font(.headline)
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("How this works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
