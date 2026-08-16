import Foundation

/// The JSON the server actually speaks.
///
/// Every detail here is pinned by CONTRACT.md in the server repo, which was
/// captured from the running server rather than inferred. Android releases
/// going back years read these same payloads, so this file is the one place
/// where "what looks like idiomatic Swift" loses to "what is on the wire":
/// hence the PascalCase property names, declared explicitly in `CodingKeys` so
/// the rest of the code can still read `expense.amount`.

// MARK: - Budget

public struct WireBudget: Codable, Sendable, Equatable {
    public var uniqueId: String
    public var name: String
    public var startDay: Int
    public var amount: Double

    enum CodingKeys: String, CodingKey {
        case uniqueId = "UniqueId"
        case name = "Name"
        case startDay = "StartDay"
        case amount = "Amount"
    }

    public init(uniqueId: String, name: String, startDay: Int, amount: Double) {
        self.uniqueId = uniqueId
        self.name = name
        self.startDay = startDay
        self.amount = amount
    }
}

// MARK: - Expense

public struct WireExpense: Codable, Sendable, Equatable {
    public var id: Int64
    public var date: Date
    public var description: String
    public var amount: Double
    public var budgetId: String
    public var categoryId: Int64?
    public var isDeleted: Bool
    public var isSystem: Bool

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case date = "Date"
        case description = "Description"
        case amount = "Amount"
        case budgetId = "BudgetId"
        case categoryId = "CategoryId"
        case isDeleted = "IsDeleted"
        case isSystem = "IsSystem"
    }

    public init(id: Int64, date: Date, description: String, amount: Double,
                budgetId: String, categoryId: Int64? = nil,
                isDeleted: Bool = false, isSystem: Bool = false) {
        self.id = id
        self.date = date
        self.description = description
        self.amount = amount
        self.budgetId = budgetId
        self.categoryId = categoryId
        self.isDeleted = isDeleted
        self.isSystem = isSystem
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        date = try WireDate.day(from: c.decode(String.self, forKey: .date))
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        budgetId = try c.decodeIfPresent(String.self, forKey: .budgetId) ?? ""
        categoryId = try c.decodeIfPresent(Int64.self, forKey: .categoryId)
        // Null on the wire for rows written before the column existed. Every
        // client has always read that as false.
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        isSystem = try c.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(WireDate.string(from: date), forKey: .date)
        try c.encode(description, forKey: .description)
        try c.encode(amount, forKey: .amount)
        try c.encode(budgetId, forKey: .budgetId)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(isDeleted, forKey: .isDeleted)
        try c.encode(isSystem, forKey: .isSystem)
    }
}

// MARK: - Category

public struct WireCategory: Codable, Sendable, Equatable {
    public var id: Int64
    public var name: String
    public var budgetId: String
    public var isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case budgetId = "BudgetId"
        case isDeleted = "IsDeleted"
    }

    public init(id: Int64, name: String, budgetId: String, isDeleted: Bool = false) {
        self.id = id
        self.name = name
        self.budgetId = budgetId
        self.isDeleted = isDeleted
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        budgetId = try c.decodeIfPresent(String.self, forKey: .budgetId) ?? ""
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
}

// MARK: - Dates on the wire

public enum WireDate {

    /// `Date` is a calendar day carried as UTC midnight — `2026-08-14T00:00:00Z`.
    ///
    /// It is read and written in UTC deliberately. The value means "the 14th",
    /// not an instant, and interpreting it in the device's zone would move it
    /// to the 13th for anyone west of Greenwich. Everything downstream keeps it
    /// in UTC for the same reason.
    public static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Parses leniently, matching Android's `SimpleDateFormat("yyyy-MM-dd")`,
    /// which succeeds by reading the leading date and ignoring the rest. The
    /// server has emitted both a bare `2026-08-14` and a full instant.
    public static func day(from text: String) throws -> Date {
        let head = String(text.prefix(10))
        let parts = head.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = utc.date(from: DateComponents(year: year, month: month, day: day))
        else {
            throw WireError.badDate(text)
        }
        return date
    }

    /// Sent as a bare `yyyy-MM-dd`, which the server parses with a regex on the
    /// leading ten characters and which cannot be shifted by a timezone.
    public static func string(from date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
}

public enum WireError: Error, Equatable {
    case badDate(String)
    case http(Int)
    case notFound
    case emptyBody
}
