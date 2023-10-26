import XCTest
@testable import SwiftGit2

@available(macOS 13.0, *)
class SwiftGit2Tests: XCTestCase {
    override func setUp() {
        SwiftGit2.initialize()
    }
}
