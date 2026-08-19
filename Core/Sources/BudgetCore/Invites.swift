import Foundation

/// An invitation to share a budget.
///
/// Sharing used to mean handing over the budget id, which is the only credential
/// the budget has and never expires. That is survivable while it travels by
/// copy-paste, and not survivable as a link — links get forwarded, quoted in
/// group chats, expanded by preview bots and written into every proxy log on the
/// way. So the link carries one of these instead: it expires, it works once, it
/// can be cancelled, and the id itself is handed back over TLS at redemption.
public struct WireInvite: Codable, Sendable, Equatable {
    public var token: String
    public var budgetId: String
    /// Built by the server, so the path lives in one place rather than in each
    /// client, an intent filter and an associated domain.
    public var url: URL
    public var expiresAt: String?
    public var maxUses: Int
    public var uses: Int

    enum CodingKeys: String, CodingKey {
        case token = "Token"
        case budgetId = "BudgetId"
        case url = "Url"
        case expiresAt = "ExpiresAt"
        case maxUses = "MaxUses"
        case uses = "Uses"
    }
}

/// Deliberately not part of `BudgetAPI`.
///
/// That protocol is the sync contract, and the sync engine has no business
/// knowing about invitations — keeping them apart also means the sync tests'
/// fake does not have to grow methods it will never call.
public protocol InviteAPI: Sendable {
    func createInvite(budgetId: String) async throws -> WireInvite
    func revokeInvite(token: String) async throws

    /// Exchanges a token for the budget it stands for, spending one use.
    ///
    /// `nil` means the invite is no longer usable — expired, cancelled, or
    /// already redeemed. The server does not say which, and neither does this:
    /// they lead to the same next step, and telling them apart would make the
    /// endpoint a report on which tokens exist.
    func redeemInvite(token: String) async throws -> WireBudget?
}

/// The invite token in an incoming link, or nil if the URL is not one.
///
/// Matching is deliberately narrow. The app claims exactly `/join/<token>` on
/// the associated domain, and anything else arriving here is either a link the
/// app should not have been handed or an attempt to get it to act on a URL it
/// does not understand.
public func inviteToken(in url: URL) -> String? {
    let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
    guard parts.count == 2, parts[0].lowercased() == "join" else { return nil }

    let token = String(parts[1])
    // Base64url, as minted by the server. Rejecting anything else here keeps
    // junk out of a URL path before it is ever sent anywhere.
    let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    guard !token.isEmpty, token.count <= 64,
          token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
    return token
}
