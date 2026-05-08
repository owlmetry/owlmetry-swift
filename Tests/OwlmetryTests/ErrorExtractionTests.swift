import XCTest
@testable import Owlmetry

private struct PlainError: Error {}

private enum AppError: Error {
    case paymentFailed(reason: String)
    case timeout
}

final class ErrorExtractionTests: XCTestCase {
    func testPlainStructErrorPopulatesType() {
        let result = ErrorExtraction.extract(
            error: PlainError(),
            userMessage: nil,
            callStack: ["frame1", "frame2"]
        )
        XCTAssertTrue(result.attributes["_error_type"]?.contains("PlainError") == true,
                      "got \(result.attributes["_error_type"] ?? "nil")")
        XCTAssertEqual(result.attributes["_error_stack"], "frame1\nframe2")
        XCTAssertNotNil(result.attributes["_error_domain"])
        XCTAssertNotNil(result.attributes["_error_code"])
    }

    func testEnumWithAssociatedValuePreservesCaseInDescribedFallback() {
        let result = ErrorExtraction.extract(
            error: AppError.paymentFailed(reason: "declined"),
            userMessage: nil,
            callStack: []
        )
        XCTAssertTrue(result.attributes["_error_type"]?.contains("AppError") == true)
        // Bridge fallback for plain Swift error enums looks like
        // "The operation couldn't be completed. (... error N.)"; the resolver
        // should fall back to String(describing:) which preserves the case.
        XCTAssertTrue(result.message.contains("paymentFailed") || result.message.contains("declined"),
                      "got message: \(result.message)")
    }

    func testNSErrorDomainAndCodeArePopulated() {
        let underlying = NSError(domain: "InnerDomain", code: 7,
                                 userInfo: [NSLocalizedDescriptionKey: "inner cause"])
        let outer = NSError(
            domain: "OuterDomain",
            code: 42,
            userInfo: [
                NSLocalizedDescriptionKey: "outer thing failed",
                NSUnderlyingErrorKey: underlying,
            ]
        )
        let result = ErrorExtraction.extract(error: outer, userMessage: nil, callStack: [])
        XCTAssertEqual(result.attributes["_error_domain"], "OuterDomain")
        XCTAssertEqual(result.attributes["_error_code"], "42")
        XCTAssertEqual(result.attributes["_error_cause_1_type"], "InnerDomain")
        XCTAssertEqual(result.attributes["_error_cause_1_message"], "inner cause")
        XCTAssertEqual(result.message, "outer thing failed")
    }

    func testCauseChainStopsAtMaxDepth() {
        var deepest = NSError(domain: "Deepest", code: 99,
                              userInfo: [NSLocalizedDescriptionKey: "bottom"])
        // Build a chain of 7 wrapped errors; expect only 5 to surface.
        for i in (0..<7).reversed() {
            deepest = NSError(
                domain: "Level\(i)",
                code: i,
                userInfo: [
                    NSLocalizedDescriptionKey: "level \(i)",
                    NSUnderlyingErrorKey: deepest,
                ]
            )
        }
        let result = ErrorExtraction.extract(error: deepest, userMessage: nil, callStack: [])
        XCTAssertEqual(result.attributes["_error_cause_1_type"], "Level1")
        XCTAssertEqual(result.attributes["_error_cause_5_type"], "Level5")
        XCTAssertNil(result.attributes["_error_cause_6_type"])
    }

    func testUserProvidedMessageWins() {
        let result = ErrorExtraction.extract(
            error: PlainError(),
            userMessage: "while uploading the photo",
            callStack: []
        )
        XCTAssertEqual(result.message, "while uploading the photo")
    }

    func testEmptyUserMessageFallsThroughToError() {
        let result = ErrorExtraction.extract(
            error: AppError.timeout,
            userMessage: "   ",
            callStack: []
        )
        XCTAssertNotEqual(result.message, "   ")
        XCTAssertFalse(result.message.isEmpty)
    }

    func testStackTruncatedAtMaxLength() {
        let line = String(repeating: "x", count: 200)
        let frames = Array(repeating: line, count: 200)
        let result = ErrorExtraction.extract(
            error: PlainError(),
            userMessage: nil,
            callStack: frames
        )
        XCTAssertEqual(result.attributes["_error_stack"]?.count, ErrorExtraction.maxStackLength)
    }

    func testTypeNameIsModuleQualified() {
        let result = ErrorExtraction.extract(
            error: PlainError(),
            userMessage: nil,
            callStack: []
        )
        // `String(reflecting: type(of:))` in tests produces something like
        // "OwlmetryTests.PlainError" — confirm the module prefix is present.
        XCTAssertTrue(result.attributes["_error_type"]?.contains(".") == true,
                      "expected module-qualified type, got \(result.attributes["_error_type"] ?? "nil")")
    }
}
