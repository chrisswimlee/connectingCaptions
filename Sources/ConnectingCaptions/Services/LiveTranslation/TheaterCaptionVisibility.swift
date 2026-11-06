import AppKit
import SwiftUI

/// Caption and chrome colors that stay readable on the Theater board.
/// Transparent Light used to paint black text with a black halo, so captions vanished on slides.
enum TheaterCaptionVisibility {
    struct Colors {
        let spoken: NSColor
        let translated: NSColor
        let reverseSpoken: NSColor
        let reverseTranslated: NSColor
        let empty: Color
        let chrome: Color
        let menuFill: Color
        let menuStroke: Color
        let shadowColor: NSColor?
        let shadowBlur: CGFloat

        func lineColors(reversePair: Bool) -> (spoken: NSColor, translated: NSColor) {
            if reversePair {
                return (self.reverseSpoken, self.reverseTranslated)
            }
            return (self.spoken, self.translated)
        }
    }

    /// True when Either way flipped a clause from the Show-as language back into I speak.
    static func usesReversePairColor(
        sourceLanguageID: String?,
        targetLanguageID: String?,
        configuredSourceID: String
    ) -> Bool {
        guard let rawSource = sourceLanguageID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawSource.isEmpty
        else {
            return false
        }
        let configured = configuredSourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configured.isEmpty,
              rawSource.caseInsensitiveCompare(configured) != .orderedSame
        else {
            return false
        }
        if let rawTarget = targetLanguageID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawTarget.isEmpty,
           rawSource.caseInsensitiveCompare(rawTarget) == .orderedSame
        {
            return false
        }
        return true
    }

    static func colors(
        appearance: TheaterAppearance,
        presentation: TheaterPresentationStyle,
        highContrast: Bool
    ) -> Colors {
        switch presentation {
        case .transparent:
            return Colors(
                spoken: NSColor.white.withAlphaComponent(highContrast ? 0.78 : 0.58),
                translated: .white,
                reverseSpoken: NSColor(
                    srgbRed: 0.56,
                    green: 0.90,
                    blue: 1.0,
                    alpha: highContrast ? 0.82 : 0.64
                ),
                reverseTranslated: NSColor(
                    srgbRed: highContrast ? 0.56 : 0.48,
                    green: highContrast ? 0.92 : 0.88,
                    blue: 1.0,
                    alpha: 1.0
                ),
                empty: Color.white.opacity(0.92),
                chrome: Color.white.opacity(0.90),
                menuFill: Color.black.opacity(0.62),
                menuStroke: Color.white.opacity(0.55),
                shadowColor: NSColor.black.withAlphaComponent(highContrast ? 0.96 : 0.90),
                shadowBlur: highContrast ? 6 : 4
            )
        case .popup:
            if appearance == .light {
                return Colors(
                    spoken: NSColor.black.withAlphaComponent(highContrast ? 0.72 : 0.50),
                    translated: .black,
                    reverseSpoken: NSColor(
                        srgbRed: 0.0,
                        green: 0.36,
                        blue: 0.68,
                        alpha: highContrast ? 0.76 : 0.56
                    ),
                    reverseTranslated: NSColor(
                        srgbRed: 0.0,
                        green: highContrast ? 0.28 : 0.36,
                        blue: highContrast ? 0.58 : 0.68,
                        alpha: 1.0
                    ),
                    empty: Color.black.opacity(0.72),
                    chrome: Color.black.opacity(0.78),
                    menuFill: Color.white.opacity(0.96),
                    menuStroke: Color.black.opacity(0.28),
                    shadowColor: highContrast ? NSColor.white.withAlphaComponent(0.85) : nil,
                    shadowBlur: highContrast ? 2 : 0
                )
            }
            return Colors(
                spoken: NSColor.white.withAlphaComponent(highContrast ? 0.78 : 0.58),
                translated: .white,
                reverseSpoken: NSColor(
                    srgbRed: 0.56,
                    green: 0.90,
                    blue: 1.0,
                    alpha: highContrast ? 0.82 : 0.64
                ),
                reverseTranslated: NSColor(
                    srgbRed: highContrast ? 0.56 : 0.48,
                    green: highContrast ? 0.92 : 0.88,
                    blue: 1.0,
                    alpha: 1.0
                ),
                empty: Color.white.opacity(0.82),
                chrome: Color.white.opacity(0.86),
                menuFill: Color.white.opacity(0.16),
                menuStroke: Color.white.opacity(0.42),
                shadowColor: highContrast ? NSColor.black.withAlphaComponent(0.85) : nil,
                shadowBlur: highContrast ? 3 : 0
            )
        }
    }

    /// Printed translations stay fully opaque. Older spoken lines stay just under full.
    static func appliedAlphas(
        spoken: NSColor,
        translated: NSColor,
        isCurrent: Bool,
        isDraft: Bool = false
    ) -> (spoken: NSColor, translated: NSColor) {
        if isCurrent {
            if isDraft {
                return (spoken, translated.withAlphaComponent(max(0.16, translated.alphaComponent * 0.4)))
            }
            return (spoken, translated)
        }
        return (spoken.withAlphaComponent(0.92), translated.withAlphaComponent(1))
    }
}
