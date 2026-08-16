import Foundation

/// Talks to the Weekly Budget server.
///
/// The awkward parts are all contract, not preference:
///
/// - `PUT` must be treated as returning nothing. The server answers 204 with an
///   empty body and the older clients throw on anything else, so nothing here
///   tries to decode a response.
/// - `GET /api/budget/{id}` answers **404** for an unknown id, and that is a
///   normal answer rather than an error — it is how joining an id that does not
///   exist fails cleanly, and how a deleted budget is noticed.
/// - The change feeds carry `X-Watermark`. Header lookup is case-insensitive
///   here because proxies rewrite header case freely and a missed header
///   silently means "never advance the watermark".
public struct LiveAPIClient: BudgetAPI {

    public static let productionURL = URL(string: "https://budget.andrewovens.com")!

    let baseURL: URL
    let session: URLSession

    public init(baseURL: URL = LiveAPIClient.productionURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private var encoder: JSONEncoder { JSONEncoder() }
    private var decoder: JSONDecoder { JSONDecoder() }

    // MARK: Budgets

    public func budget(id: String) async throws -> WireBudget? {
        let (data, response) = try await send(request("api/budget/\(escaped(id))"))
        if response.statusCode == 404 { return nil }
        try check(response)
        return try decoder.decode(WireBudget.self, from: data)
    }

    public func createBudget(_ budget: WireBudget) async throws -> WireBudget {
        let (data, response) = try await send(try request("api/budget", method: "POST", body: budget))
        try check(response)
        return try decoder.decode(WireBudget.self, from: data)
    }

    public func updateBudget(_ budget: WireBudget) async throws {
        let (_, response) = try await send(
            try request("api/budget/\(escaped(budget.uniqueId))", method: "PUT", body: budget))
        try check(response)
    }

    // MARK: Change feeds

    public func expenses(budgetId: String, since: String?) async throws -> Page<WireExpense> {
        try await feed("api/budget/\(escaped(budgetId))/Expenses", since: since)
    }

    public func categories(budgetId: String, since: String?) async throws -> Page<WireCategory> {
        try await feed("api/budget/\(escaped(budgetId))/Categories", since: since)
    }

    private func feed<Item: Decodable & Sendable>(_ path: String, since: String?) async throws -> Page<Item> {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        // An absent or empty watermark means "everything", which is exactly
        // what a first sync wants.
        components.queryItems = [URLQueryItem(name: "watermark", value: since ?? "")]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await send(urlRequest)
        try check(response)
        return Page(items: try decoder.decode([Item].self, from: data),
                    watermark: response.value(forHTTPHeaderField: "X-Watermark"))
    }

    /// Expenses for the budget week containing an instant, as unix milliseconds.
    ///
    /// Only used to cross-check against the server's own idea of a week; the
    /// app reads its own store rather than this, so it works offline.
    public func week(budgetId: String, containing date: Date) async throws -> [WireExpense] {
        let millis = Int64(date.timeIntervalSince1970 * 1000)
        let (data, response) = try await send(
            request("api/budget/\(escaped(budgetId))/Week/\(millis)"))
        try check(response)
        return try decoder.decode([WireExpense].self, from: data)
    }

    // MARK: Expenses

    public func createExpense(_ expense: WireExpense) async throws -> WireExpense {
        let (data, response) = try await send(try request("api/expense", method: "POST", body: expense))
        try check(response)
        return try decoder.decode(WireExpense.self, from: data)
    }

    public func updateExpense(_ expense: WireExpense) async throws {
        let (_, response) = try await send(
            try request("api/expense/\(expense.id)", method: "PUT", body: expense))
        try check(response)
    }

    @discardableResult
    public func deleteExpense(id: Int64) async throws -> WireExpense {
        let (data, response) = try await send(request("api/expense/\(id)", method: "DELETE"))
        try check(response)
        return try decoder.decode(WireExpense.self, from: data)
    }

    // MARK: Categories

    public func createCategory(_ category: WireCategory) async throws -> WireCategory {
        let (data, response) = try await send(try request("api/categories", method: "POST", body: category))
        try check(response)
        return try decoder.decode(WireCategory.self, from: data)
    }

    public func updateCategory(_ category: WireCategory) async throws {
        let (_, response) = try await send(
            try request("api/categories/\(category.id)", method: "PUT", body: category))
        try check(response)
    }

    @discardableResult
    public func deleteCategory(id: Int64) async throws -> WireCategory {
        let (data, response) = try await send(request("api/categories/\(id)", method: "DELETE"))
        try check(response)
        return try decoder.decode(WireCategory.self, from: data)
    }

    // MARK: Plumbing

    private func escaped(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        return urlRequest
    }

    private func request(_ path: String, method: String, body: some Encodable) throws -> URLRequest {
        var urlRequest = request(path, method: method)
        urlRequest.httpBody = try encoder.encode(body)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return urlRequest
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WireError.http(-1) }
        return (data, http)
    }

    private func check(_ response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw WireError.http(response.statusCode)
        }
    }
}
