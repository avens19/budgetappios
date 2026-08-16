import SwiftUI
import SwiftData
import BudgetCore

/// Add and edit are the same form. The only differences are the title, the
/// destructive actions, and whether there is a row to update.
struct ExpenseEditor: View {
    @Environment(BudgetSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let budget: LocalBudget
    let expense: LocalExpense?
    let defaultDate: Date

    @State private var amount = ""
    @State private var detail = ""
    @State private var localDate = Date()
    @State private var categoryId: Int64?
    @State private var newCategoryName = ""
    @State private var addingCategory = false
    @State private var confirmingDelete = false
    @FocusState private var amountFocused: Bool

    @Query private var categories: [LocalCategory]

    init(budget: LocalBudget, expense: LocalExpense?, defaultDate: Date) {
        self.budget = budget
        self.expense = expense
        self.defaultDate = defaultDate
        let id = budget.uniqueId
        _categories = Query(filter: #Predicate<LocalCategory> { $0.budgetId == id },
                            sort: [SortDescriptor(\.name)])
    }

    private var live: [LocalCategory] { categories.filter { !$0.isDeleted } }
    private var isEditing: Bool { expense != nil }

    private var parsedAmount: Double? {
        Double(amount.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        parsedAmount != nil && !detail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Amount first and focused: it is the one field that always
                    // has to be typed, and the keyboard should already be up.
                    TextField("0", text: $amount)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .focused($amountFocused)
                        .accessibilityLabel("Amount")
                        .accessibilityIdentifier("amountField")
                } header: {
                    Text("Amount")
                } footer: {
                    Text("Money coming in? Enter it with a minus sign.")
                }

                Section {
                    TextField("Description", text: $detail)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("descriptionField")

                    DatePicker("Date", selection: $localDate, displayedComponents: .date)

                    Picker("Category", selection: $categoryId) {
                        Text("No category").tag(Int64?.none)
                        ForEach(live) { category in
                            Text(category.name).tag(Int64?.some(category.id))
                        }
                    }

                    Button {
                        newCategoryName = ""
                        addingCategory = true
                    } label: {
                        Label("New category", systemImage: "plus.circle")
                    }
                }

                if isEditing {
                    Section {
                        Button {
                            if let expense {
                                session.copyToNextWeek(expense, in: budget)
                                dismiss()
                            }
                        } label: {
                            Label("Copy to next week", systemImage: "calendar.badge.plus")
                        }

                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete expense", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit expense" : "Add expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                        .accessibilityIdentifier("saveExpense")
                }
            }
            .alert("New category", isPresented: $addingCategory) {
                TextField("Name", text: $newCategoryName)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    categoryId = session.addCategory(named: name, to: budget).id
                }
            }
            .confirmationDialog("Delete this expense?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let expense { session.deleteExpense(expense) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let expense {
            amount = String(format: "%g", expense.amount)
            detail = expense.detail
            categoryId = expense.categoryId
        }
        // The picker works in the device's zone; budget dates are UTC days.
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let parts = WireDate.utc.dateComponents([.year, .month, .day],
                                                from: expense?.date ?? defaultDate)
        localDate = local.date(from: parts) ?? Date()

        if !isEditing {
            // A beat, or the field is not in the hierarchy yet and focus is lost.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { amountFocused = true }
        }
    }

    private func save() {
        guard let value = parsedAmount else { return }
        let text = detail.trimmingCharacters(in: .whitespaces)
        let day = BudgetCalendar.today(now: localDate)

        if let expense {
            session.updateExpense(expense, date: day, detail: text,
                                  amount: value, categoryId: categoryId)
        } else {
            session.addExpense(to: budget, date: day, detail: text,
                               amount: value, categoryId: categoryId)
        }
        dismiss()
    }
}
