import XCTest
@testable import ConnectingCaptions_Debug

final class KeywordAnchorTests: XCTestCase {
    private func anchor(
        _ lines: String,
        misspelled: [String] = []
    ) -> KeywordAnchor {
        let terms = lines.components(separatedBy: .newlines).compactMap(KeywordTerm.parse(line:))
        let flagged = Set(misspelled)
        return KeywordAnchor(terms: terms) { word, _ in flagged.contains(word) }
    }

    func testEmptyListIsIdentityAndDoesNoWork() {
        var asked = false
        let anchor = KeywordAnchor(terms: []) { _, _ in
            asked = true
            return true
        }
        XCTAssertEqual(anchor.apply("buy Appl today", languageID: "en"), "buy Appl today")
        XCTAssertFalse(asked)
        XCTAssertTrue(anchor.matchedTerms(in: "Appl").isEmpty)
    }

    func testExactTickerUsesTheFileSpelling() {
        let anchor = self.anchor("AAPL")
        XCTAssertEqual(anchor.apply("buy aapl today", languageID: "en"), "buy AAPL today")
    }

    func testArrowReplacesTheMishearing() {
        let anchor = self.anchor("nightingale fund -> Nightingale")
        XCTAssertEqual(
            anchor.apply("the nightingale fund closed.", languageID: "en"),
            "the Nightingale closed."
        )
    }

    func testMisspelledWordIsCorrectedAndARealWordIsLeftAlone() {
        let anchor = self.anchor("Apple", misspelled: ["Appl"])
        XCTAssertEqual(anchor.apply("Appl closed", languageID: "en"), "Apple closed")
        XCTAssertEqual(anchor.apply("apply closed", languageID: "en"), "apply closed")
    }

    func testJapaneseSubstringMatch() {
        let anchor = self.anchor("トヨタ -> Toyota")
        XCTAssertEqual(anchor.apply("これはトヨタです", languageID: "ja"), "これはToyotaです")
    }

    func testPunctuationStaysPut() {
        let anchor = self.anchor("AAPL")
        XCTAssertEqual(anchor.apply("Hello,  aapl!", languageID: "en"), "Hello,  AAPL!")
    }

    @MainActor
    func testListStaysFrozenUntilTheNextCapture() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("keywords-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            KeywordAnchorSession.shared.capture(from: folder)
        }
        let file = folder.appendingPathComponent("terms.txt")
        try "AAPL\n".write(to: file, atomically: true, encoding: .utf8)
        KeywordAnchorSession.shared.capture(from: folder)
        try "AAPL\nMSFT\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(KeywordAnchorSession.shared.apply("msft", languageID: "en"), "msft")
        KeywordAnchorSession.shared.capture(from: folder)
        XCTAssertEqual(KeywordAnchorSession.shared.apply("msft", languageID: "en"), "MSFT")
    }

    @MainActor
    func testConfirmPathUsesTheSessionAnchor() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("keywords-confirm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            KeywordAnchorSession.shared.capture(from: folder)
        }
        try "AAPL\n".write(to: folder.appendingPathComponent("terms.txt"), atomically: true, encoding: .utf8)
        KeywordAnchorSession.shared.capture(from: folder)
        XCTAssertEqual(
            KeywordAnchorSession.shared.apply("heard aapl", languageID: "ko"),
            "heard AAPL"
        )
    }

    func testMatchedTermsAreOnlyTheKeywordsInTheClause() {
        let anchor = self.anchor("Apple\nNightingale")
        XCTAssertEqual(anchor.matchedTerms(in: "See Nightingale today"), ["Nightingale"])
        XCTAssertTrue(anchor.matchedTerms(in: "See the board").isEmpty)
    }

    func testFolderLoadCapsAtTwoThousandTerms() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("keywords-cap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let lines = (0 ..< 2_001).map { "Term\($0)" }.joined(separator: "\n")
        try lines.write(to: folder.appendingPathComponent("many.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(KeywordTerm.load(from: folder).count, KeywordTerm.maxCount)
    }
}
