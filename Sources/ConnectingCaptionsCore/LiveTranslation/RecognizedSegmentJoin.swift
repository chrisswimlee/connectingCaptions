import Foundation

/// Joins recognizer segments into one caption. Every recognizer, Mac and iOS,
/// uses this so a line reads the same on each screen.
///
/// Thai, Japanese, and Chinese put no space between words, so two segments in
/// those scripts join with nothing between them. Korean is written with spaces
/// and joins with one, like English.
nonisolated public enum RecognizedSegmentJoin {
    public static func join(_ left: String, _ right: String) -> String {
        if right.isEmpty { return left }
        if left.isEmpty { return right }
        if self.isUnspaced(left.last), self.isUnspaced(right.first) {
            return left + right
        }
        return left + " " + right
    }

    public static func isUnspaced(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.unicodeScalars.contains { scalar in
            (0x0E00...0x0E7F).contains(scalar.value) // Thai
                || (0x3000...0x303F).contains(scalar.value) // CJK punctuation (。、)
                || (0x3040...0x30FF).contains(scalar.value) // Hiragana, Katakana
                || (0x31F0...0x31FF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value) // Han
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xFF01...0xFF0F).contains(scalar.value) // Fullwidth ！？
                || (0xFF1A...0xFF1F).contains(scalar.value)
                || (0xFF66...0xFF9D).contains(scalar.value) // Halfwidth Katakana
        }
    }
}
