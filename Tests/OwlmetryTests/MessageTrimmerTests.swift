import XCTest
@testable import Owlmetry

final class MessageTrimmerTests: XCTestCase {
    func testEmptyReturnsEmpty() {
        XCTAssertEqual(MessageTrimmer.trim(""), "")
    }

    func testShortMessagePassesThrough() {
        let message = "user clicked signup"
        XCTAssertEqual(MessageTrimmer.trim(message), message)
    }

    func testExactly2000CharsPassesThrough() {
        let message = String(repeating: "a", count: 2000)
        XCTAssertEqual(MessageTrimmer.trim(message), message)
    }

    func testOver2000CharsTrimmed() {
        let message = String(repeating: "a", count: 5000)
        let result = MessageTrimmer.trim(message)
        XCTAssertEqual(result.count, 2000)
        XCTAssertEqual(result, String(repeating: "a", count: 2000))
    }
}
