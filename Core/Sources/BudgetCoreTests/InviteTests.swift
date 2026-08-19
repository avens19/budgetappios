import Foundation
import BudgetCore

/// URL parsing for incoming invite links.
///
/// The app is handed a URL by the system and immediately turns part of it into a
/// request path, so what it accepts matters more than the happy case suggests.
enum InviteLinkTests {

    static func test_readsTheToken() {
        XCTAssertEqual(inviteToken(in: URL(string: "https://budget.andrewovens.com/join/ROyjAotKPeuoXbCtQaOIRg")!),
                    "ROyjAotKPeuoXbCtQaOIRg")
    }

    static func test_acceptsBase64urlAlphabet() {
        // Real tokens contain - and _, and dropping those would reject roughly
        // one link in four for no reason.
        XCTAssertEqual(inviteToken(in: URL(string: "https://budget.andrewovens.com/join/Jcxgvw1UDNHOIBX7mn-dlw")!),
                    "Jcxgvw1UDNHOIBX7mn-dlw")
        XCTAssertEqual(inviteToken(in: URL(string: "https://budget.andrewovens.com/join/eI_VA_2r2CeqpFqQPhVLYA")!),
                    "eI_VA_2r2CeqpFqQPhVLYA")
    }

    static func test_rejectsEverythingElse() {
        // Other paths on the same domain: the association file claims only
        // /join/*, but nothing stops a URL arriving by another route.
        XCTAssertNil(inviteToken(in: URL(string: "https://budget.andrewovens.com/")!))
        XCTAssertNil(inviteToken(in: URL(string: "https://budget.andrewovens.com/Apps")!))
        XCTAssertNil(inviteToken(in: URL(string: "https://budget.andrewovens.com/join")!))
        XCTAssertNil(inviteToken(in: URL(string: "https://budget.andrewovens.com/join/")!))
        // A budget URL is not an invite, and must not be mistaken for one.
        XCTAssertNil(inviteToken(in: URL(string: "https://budget.andrewovens.com/Budget/abc/Edit")!))
        // Extra segments: /join/a/b is not a token called "a".
        XCTAssertNil(inviteToken(in: URL(string: "https://budget.andrewovens.com/join/abc/def")!))
    }

    static func test_rejectsPathTricks() {
        // The token goes straight into a request path. Anything that could
        // change the shape of that path has to be refused here.
        XCTAssertNil(inviteToken(in: URL(string: "https://budget.andrewovens.com/join/..%2F..%2Fapi%2Fbudget")!))
        XCTAssertNil(inviteToken(in: URL(string: "https://budget.andrewovens.com/join/tok%20en")!))
        XCTAssertNil(inviteToken(in: URL(string: "https://budget.andrewovens.com/join/tok.en")!))
        XCTAssertNil(inviteToken(in: URL(string: "https://budget.andrewovens.com/join/\(String(repeating: "a", count: 65))")!))
    }

    static func test_ignoresQueryAndFragment() {
        // Chat clients append tracking parameters, and the token is the path.
        XCTAssertEqual(inviteToken(in: URL(string: "https://budget.andrewovens.com/join/ROyjAotKPeuoXbCtQaOIRg?utm_source=x")!),
                    "ROyjAotKPeuoXbCtQaOIRg")
    }
}
