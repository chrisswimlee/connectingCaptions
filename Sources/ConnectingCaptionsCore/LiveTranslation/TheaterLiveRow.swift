import Foundation

/// Strips a trailing mark so a restitch can grow a clause. The mark arrives
/// with the accepted sentence.
public enum TheaterLiveRow {
    public static func openText(_ text: String) -> String {
        var open = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = open.last, ".…?!。！？".contains(last) {
            open.removeLast()
        }
        return open.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// I speak for this leftover. The macOS app wires this to `SpokenLanguageResolver`.
public enum ListenLanguageID {
    public static var resolve: @Sendable (String) -> String = { _ in
        TranslationLanguageCatalog.english.id
    }

    public static func current(for text: String) -> String {
        self.resolve(text)
    }
}
