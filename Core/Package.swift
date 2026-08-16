// swift-tools-version: 6.0
import PackageDescription

// The parts of the app that are not SwiftUI and not SwiftData: wire types, the
// sync engine, the budget-week calendar maths, the category palette.
//
// It lives in its own package so this logic can be built and tested from the
// command line on macOS, without the iOS simulator in the loop. That matters
// more than it sounds: the sync engine is where a wrong answer quietly loses
// somebody's data, and it is the one part that has to agree exactly with the
// Android client and the server.
let package = Package(
    name: "BudgetCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BudgetCore", targets: ["BudgetCore"]),
    ],
    targets: [
        .target(name: "BudgetCore"),
        // An executable rather than a .testTarget: XCTest and swift-testing
        // both live inside Xcode and SwiftPM cannot link either from the
        // Command Line Tools toolchain. `swift run BudgetCoreTests` works
        // anywhere Swift is installed, including CI without Xcode.
        .executableTarget(name: "BudgetCoreTests", dependencies: ["BudgetCore"]),
        // Hits a real server and writes to it, so it is kept separate from the
        // unit suite: `swift run BudgetCoreLive [base-url]`.
        .executableTarget(name: "BudgetCoreLive", dependencies: ["BudgetCore"]),
    ]
)
