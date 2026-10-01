import XCTest
@testable import ConnectingCaptions_Debug

final class ZZAuditProbeTests: XCTestCase {
    func testProbeJapaneseOpeners() {
        let openers = ["ところで明日は雨です", "とても楽しかったです", "よろしくお願いします", "しばらく休みます", "かなり難しいです", "がんばります", "したがって結論です"]
        for rest in openers {
            print("PROBE continues=\(TranslationClauseSegmenter.japaneseRemainderContinuesClause(rest)) newSentence=\(TranslationClauseSegmenter.continuesAsNewSentence(rest, languageID: "ja")) \(rest)")
        }
        let split = TranslationClauseSegmenter.split("今日は休みです。とても楽しかったです。", languageID: "ja")
        print("PROBE split completed=\(split.completed) tail=\(split.tail)")
        let merged = TranslationClauseSegmenter.japaneseRowContinuation(row: "今日は休みです。", unit: "とても楽しかったです。", languageID: "ja")
        print("PROBE rowMerge=\(merged ?? "nil")")
    }
}
