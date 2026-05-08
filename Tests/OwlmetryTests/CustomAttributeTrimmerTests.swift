import XCTest
@testable import Owlmetry

final class CustomAttributeTrimmerTests: XCTestCase {
    func testNilReturnsNil() {
        XCTAssertNil(CustomAttributeTrimmer.trim(nil))
    }

    func testEmptyReturnsEmpty() {
        let result = CustomAttributeTrimmer.trim([:])
        XCTAssertEqual(result, [:])
    }

    func testShortValuesPassThrough() {
        let attributes = ["key": "short value"]
        let result = CustomAttributeTrimmer.trim(attributes)
        XCTAssertEqual(result, attributes)
    }

    func testExactly200CharsPassThrough() {
        let value = String(repeating: "a", count: 200)
        let result = CustomAttributeTrimmer.trim(["key": value])
        XCTAssertEqual(result?["key"], value)
    }

    func testOver200CharsTrimmed() {
        let value = String(repeating: "a", count: 250)
        let result = CustomAttributeTrimmer.trim(["key": value])
        let expected = String(repeating: "a", count: 200)
        XCTAssertEqual(result?["key"], expected)
    }

    func testMultipleKeysIndependent() {
        let short = "ok"
        let long = String(repeating: "b", count: 300)
        let result = CustomAttributeTrimmer.trim(["short": short, "long": long])
        XCTAssertEqual(result?["short"], short)
        XCTAssertEqual(result?["long"]?.count, 200)
    }

    func testErrorStackKeyKeepsLongerValueViaOverride() {
        let stack = String(repeating: "f", count: 5000)
        let result = CustomAttributeTrimmer.trim(["_error_stack": stack])
        XCTAssertEqual(result?["_error_stack"]?.count, 5000)
    }

    func testErrorStackKeyTruncatesAtOverrideCap() {
        let stack = String(repeating: "f", count: 20000)
        let result = CustomAttributeTrimmer.trim(["_error_stack": stack])
        XCTAssertEqual(result?["_error_stack"]?.count, 16000)
    }

    func testNonOverrideErrorKeyStillCapsAt200() {
        let typeName = String(repeating: "T", count: 500)
        let result = CustomAttributeTrimmer.trim(["_error_type": typeName])
        XCTAssertEqual(result?["_error_type"]?.count, 200)
    }
}
