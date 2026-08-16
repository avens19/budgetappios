import Foundation

/// A very small test harness.
///
/// XCTest and swift-testing both live inside Xcode, and SwiftPM cannot link
/// either from the Command Line Tools toolchain. Rather than leave the sync
/// engine untested until someone opens Xcode, the suite runs as a plain
/// executable: `swift run BudgetCoreTests`.
///
/// The assertions are spelled like XCTest's on purpose, so these files can be
/// dropped into a real test target later with an import and nothing else.
enum Check {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var currentTest = ""
}

func XCTAssertTrue(_ condition: @autoclosure () throws -> Bool,
                   _ message: String = "",
                   file: StaticString = #filePath, line: UInt = #line) rethrows {
    Check.checks += 1
    if !(try condition()) {
        let detail = message.isEmpty ? "" : " — \(message)"
        Check.failures.append("\(Check.currentTest): assertion failed\(detail) (\(shortFile(file)):\(line))")
    }
}

func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
                                  _ message: String = "",
                                  file: StaticString = #filePath, line: UInt = #line) rethrows {
    Check.checks += 1
    let (left, right) = (try a(), try b())
    if left != right {
        let detail = message.isEmpty ? "" : " — \(message)"
        Check.failures.append("\(Check.currentTest): \(left) != \(right)\(detail) (\(shortFile(file)):\(line))")
    }
}

func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T,
                             _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
    Check.checks += 1
    do {
        _ = try expression()
        Check.failures.append("\(Check.currentTest): expected a throw but none happened (\(shortFile(file)):\(line))")
    } catch {
        // Expected.
    }
}

private func shortFile(_ file: StaticString) -> String {
    URL(fileURLWithPath: "\(file)").lastPathComponent
}

/// Runs one test, recording which one is active so failures name themselves.
func test(_ name: String, _ body: () throws -> Void) {
    Check.currentTest = name
    do { try body() } catch {
        Check.failures.append("\(name): threw \(error)")
    }
}

func test(_ name: String, _ body: () async throws -> Void) async {
    Check.currentTest = name
    do { try await body() } catch {
        Check.failures.append("\(name): threw \(error)")
    }
}

func report() -> Int32 {
    if Check.failures.isEmpty {
        print("  \(Check.checks) assertions passed")
        return 0
    }
    print("  \(Check.failures.count) FAILURE(S) of \(Check.checks) assertions:\n")
    for failure in Check.failures { print("    \(failure)") }
    return 1
}
