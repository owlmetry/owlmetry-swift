import XCTest
@testable import Owlmetry

/// Covers the `[String: String?]` public API shape — callers can pass
/// optional values directly and nils are silently dropped before the
/// attributes reach the event pipeline.
final class OwlAttributesTests: XCTestCase {
    func testEmptyDictReturnsNil() {
        XCTAssertNil(Owl.cleanAttributes([:]))
    }

    func testAllNonNilPassThrough() {
        let result = Owl.cleanAttributes(["a": "x", "b": "y"])
        XCTAssertEqual(result, ["a": "x", "b": "y"])
    }

    func testAllNilReturnsNil() {
        XCTAssertNil(Owl.cleanAttributes(["a": nil, "b": nil]))
    }

    func testMixedNilFilteredOut() {
        let result = Owl.cleanAttributes(["a": "x", "b": nil, "c": "z"])
        XCTAssertEqual(result, ["a": "x", "c": "z"])
    }

    func testEmptyStringIsKept() {
        // Empty string and nil are different — only nil is dropped.
        let result = Owl.cleanAttributes(["a": ""])
        XCTAssertEqual(result, ["a": ""])
    }
}
