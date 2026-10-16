//
//  SettingsSearch.swift
//  fluid
//
//  Search metadata and fuzzy matching for the Settings sidebar.
//

import AppKit
import Foundation
import SwiftUI

enum SettingsSearchTarget: Hashable {
    case liveTranslation
    case theaterAppearance
    case theaterAdvanced
    case theaterPlayback
    case translateInsertShortcut
    case captionListenShortcut
    case general
    case launchAtStartup
    case showWindowAtLogin
    case dockVisibility
    case accentColor
    case transcriptionSounds
    case automaticUpdates
    case commercialLicense

    case dictation
    case microphonePermission
    case globalHotkey
    case primaryDictationShortcuts
    case cancelRecordingShortcut
    case pasteLastTranscriptionShortcut
    case activationMode
    case copyToClipboard
    case textInsertionMode
    case spokenSend
    case transcriptionHistory
    case historyRetention
    case audioHistory
    case usageStreak
    case skipSilentRecordings
    case pauseMedia
    case dictionarySuggestions
    case accessibilityPermission
    case textFormatting

    case notifications
    case aiEnhancementFailures
    case microphoneChanges

    case audio
    case inputDevicePriority
    case outputDevice

    case overlay
    case overlaySensitivity
    case overlayPosition
    case transcriptionPreviewLength
    case overlayStyle
    case livePreview
    case bottomOffset

    case dataAndDiagnostics
    case backupAndRestore
    case audioStorage
    case debugLogs
    case experimental
    case fasterLongDictation
    case historyPerformance
    case aiProviders

    var section: SettingsSection {
        switch self {
        case .liveTranslation, .theaterAppearance, .theaterAdvanced, .theaterPlayback, .captionListenShortcut:
            return .translation

        case .translateInsertShortcut:
            return .speakAndType

        case .general,
             .launchAtStartup,
             .showWindowAtLogin,
             .dockVisibility,
             .accentColor,
             .transcriptionSounds,
             .automaticUpdates,
             .commercialLicense:
            return .general

        case .accessibilityPermission:
            return .speakAndType

        case .transcriptionHistory, .historyRetention, .audioHistory, .audioStorage:
            return .dataAndDiagnostics

        case .dictation,
             .pauseMedia,
             .textFormatting,
             .globalHotkey,
             .dictionarySuggestions,
             .primaryDictationShortcuts,
             .cancelRecordingShortcut,
             .pasteLastTranscriptionShortcut,
             .activationMode,
             .copyToClipboard,
             .textInsertionMode,
             .spokenSend,
             .usageStreak,
             .skipSilentRecordings,
             .aiEnhancementFailures:
            return .dictation

        case .notifications, .microphoneChanges:
            return .notifications

        case .audio, .inputDevicePriority, .outputDevice, .microphonePermission:
            return .audio

        case .overlay,
             .overlaySensitivity,
             .overlayPosition,
             .transcriptionPreviewLength,
             .overlayStyle,
             .livePreview,
             .bottomOffset:
            return .dictation

        case .aiProviders:
            return .aiProviders

        case .dataAndDiagnostics, .backupAndRestore, .debugLogs:
            return .dataAndDiagnostics

        case .experimental, .fasterLongDictation, .historyPerformance:
            return .experimental
        }
    }
}

extension SettingsSection {
    var searchTarget: SettingsSearchTarget {
        switch self {
        case .translation: return .liveTranslation
        case .speakAndType: return .translateInsertShortcut
        case .general: return .general
        case .dictation: return .dictation
        case .aiProviders: return .aiProviders
        case .notifications: return .notifications
        case .audio: return .audio
        case .dataAndDiagnostics: return .dataAndDiagnostics
        case .experimental: return .experimental
        }
    }
}

struct SettingsSearchResult: Identifiable, Equatable {
    let target: SettingsSearchTarget
    let score: Int

    var id: SettingsSearchTarget {
        self.target
    }

    var section: SettingsSection {
        self.target.section
    }
}

enum SettingsSearchIndex {
    private static let queryStopWords: Set<String> = ["and", "for", "from", "in", "of", "or", "the", "to", "with"]

    private struct Entry {
        let target: SettingsSearchTarget
        let title: String
        let terms: [String]
    }

    private struct WeightedField {
        let text: String
        let weight: Int
    }

    private static let entries: [Entry] = [
        .init(
            target: .liveTranslation,
            title: AppLanguage.text("Theater"),
            terms: [
                "translate theater captions language pair apple translation I speak show as",
                "voice transcription translate mode",
                "voice engine speech to text apple speech analyzer language packs apple translation download",
                "translation engine language packs",
            ]
        ),
        .init(
            target: .theaterAppearance,
            title: AppLanguage.text("Caption appearance"),
            terms: [
                "caption font size spoken line source translation theater window captions only dark light appearance theme",
                "original language spoken line under each delivered sentence",
                "caption font size spoken line source translation theater window captions only dark light appearance theme",
                "popup pop-up transparent overlay board slides keynote see-through caption bar caption plate",
                "menu bar theater font size plate theme position overlay tools",
                "screen share screenshots zoom meet slides window capture projector OBS",
                "high contrast show original text window style",
                "talk notes notes pdf pptx powerpoint deck rtf markdown json glossary names",
                "pace cue teleprompter behind caught up last print",
                "voice transcription translate mode",
            ]
        ),
        .init(
            target: .theaterAdvanced,
            title: AppLanguage.text("Advanced captions"),
            terms: [
                "either way whisper bidirectional two languages",
                "caption animation timing line print print gap word letter fade",
                "presenter shortcuts hotkeys control option",
                "save transcript markdown vtt session export when listen stops",
            ]
        ),
        .init(
            target: .theaterPlayback,
            title: AppLanguage.text("Playback and session"),
            terms: ["speak captions speak on voice output", "clear captions board archive wipe reset"]
        ),
        .init(
            target: .captionListenShortcut,
            title: AppLanguage.text("Listen Shortcut"),
            terms: ["listen hotkey shortcut theater captions"]
        ),
        .init(
            target: .translateInsertShortcut,
            title: AppLanguage.text("Speak and type"),
            terms: [
                "speak and type insert section listen and type hotkey shortcut speak translate type into app quick bar release",
                "accessibility permission system settings authorize typing",
            ]
        ),
        .init(target: .general, title: AppLanguage.text("General"), terms: ["app settings preferences startup menu bar dock"]),
        .init(
            target: .launchAtStartup,
            title: AppLanguage.text("Launch at startup"),
            terms: ["Automatically start connectingCaptions when you log in", "login startup boot open"]
        ),
        .init(
            target: .showWindowAtLogin,
            title: AppLanguage.text("Show window when launched at login"),
            terms: ["starts silently in the menu bar", "login window visibility"]
        ),
        .init(
            target: .dockVisibility,
            title: AppLanguage.text("Hide from Dock & App Switcher"),
            terms: ["menu bar only", "dock icon command tab cmd tab app switcher"]
        ),
        .init(target: .accentColor, title: AppLanguage.text("Accent Color"), terms: ["appearance theme tint colour color preset default caption gold"]),
        .init(
            target: .automaticUpdates,
            title: AppLanguage.text("Automatic Updates"),
            terms: ["beta releases check for updates release notes rollback previous builds version"]
        ),
        .init(
            target: .commercialLicense,
            title: AppLanguage.text("Commercial License"),
            terms: [
                "license commercial enterprise SLA IT legal procurement named organization",
                "for work email to buy licensed to activation key air-gapped",
                "price $60 seat Mac year SLA MDM Jamf Fleet pkg",
                "seat list Jamf Fleet MDM pkg audit log caption policy activity log backup restore",
            ]
        ),

        .init(target: .dictation, title: AppLanguage.text("Dictation"), terms: ["typing transcription keyboard preferences"]),
        .init(
            target: .microphonePermission,
            title: AppLanguage.text("Microphone Permission"),
            terms: ["mic access authorization privacy grant denied system settings"]
        ),
        .init(target: .globalHotkey, title: AppLanguage.text("Global Hotkey"), terms: ["keyboard shortcut activation accessibility"]),
        .init(
            target: .primaryDictationShortcuts,
            title: AppLanguage.text("Primary Dictation Shortcuts"),
            terms: ["keyboard shortcut mouse button record hotkey"]
        ),
        .init(
            target: .cancelRecordingShortcut,
            title: AppLanguage.text("Cancel Recording"),
            terms: ["dismiss overlay stop hotkey shortcut"]
        ),
        .init(
            target: .pasteLastTranscriptionShortcut,
            title: AppLanguage.text("Paste Last Transcription"),
            terms: ["reinsert recent text hotkey shortcut clipboard"]
        ),
        .init(target: .activationMode, title: AppLanguage.text("Activation Mode"), terms: ["hold toggle hotkey behavior"]),
        .init(
            target: .copyToClipboard,
            title: AppLanguage.text("Copy to Clipboard"),
            terms: ["automatically copy transcribed text pasteboard backup"]
        ),
        .init(
            target: .textInsertionMode,
            title: AppLanguage.text("Text Insertion Mode"),
            terms: ["type text copy paste clipboard reliable insertion delivery"]
        ),
        .init(
            target: .spokenSend,
            title: AppLanguage.text("Spoken Send"),
            terms: ["send immediately phrase command enter return submit voice"]
        ),
        .init(
            target: .transcriptionHistory,
            title: AppLanguage.text("Save Transcription History"),
            terms: ["stats tracking privacy remember transcript"]
        ),
        .init(
            target: .historyRetention,
            title: AppLanguage.text("Keep History"),
            terms: ["retention days year forever prune sqlite history limit"]
        ),
        .init(
            target: .audioHistory,
            title: AppLanguage.text("Save Audio With History"),
            terms: ["store microphone recording locally dictation audio"]
        ),
        .init(
            target: .usageStreak,
            title: AppLanguage.text("Weekends Don't Break Streak"),
            terms: ["Saturday Sunday stats usage streak weekday"]
        ),
        .init(
            target: .skipSilentRecordings,
            title: AppLanguage.text("Skip Silent Recordings"),
            terms: ["silence quiet speech avoid transcription"]
        ),
        .init(
            target: .dictionarySuggestions,
            title: AppLanguage.text("Auto-Learn Corrections"),
            terms: ["automatic corrections learn words custom dictionary frequency ignore import lecture terms glossary pack"]
        ),
        .init(
            target: .accessibilityPermission,
            title: AppLanguage.text("Accessibility Permission"),
            terms: ["global hotkey access macOS system settings authorize"]
        ),
        .init(
            target: .textFormatting,
            title: AppLanguage.text("Text Formatting"),
            terms: [
                "Lowercase First Letter Remove Trailing Period Slash Commands @ Formatting",
                "Space Between Dictations Smart Capitalization punctuation uppercase symbols mentions",
            ]
        ),

        .init(target: .notifications, title: AppLanguage.text("Notifications"), terms: ["alerts warnings"]),
        .init(
            target: .aiEnhancementFailures,
            title: AppLanguage.text("AI Enhancement Failures"),
            terms: ["notify processing error raw transcription alert"]
        ),
        .init(
            target: .microphoneChanges,
            title: AppLanguage.text("Microphone Changes"),
            terms: ["mic device lost changed alert notification"]
        ),

        .init(target: .audio, title: AppLanguage.text("Audio"), terms: ["sound devices microphone speaker"]),
        .init(
            target: .inputDevicePriority,
            title: AppLanguage.text("Input Device Priority"),
            terms: ["microphone mic order drag reorder default restore removed unavailable active"]
        ),
        .init(
            target: .outputDevice,
            title: AppLanguage.text("Output Device"),
            terms: ["speaker headphones audio system default refresh loading"]
        ),

        .init(
            target: .aiProviders,
            title: AppLanguage.text("AI Providers"),
            terms: ["ai providers local models api cleanup styles dictation polish"]
        ),
        .init(target: .overlay, title: AppLanguage.text("Recording Overlay"), terms: ["recording indicator notch pill visualizer overlay"]),
        .init(
            target: .overlaySensitivity,
            title: AppLanguage.text("Sensitivity"),
            terms: ["audio visualizer sound input more less threshold"]
        ),
        .init(
            target: .overlayPosition,
            title: AppLanguage.text("Overlay Position"),
            terms: ["recording indicator screen notch pill bottom location"]
        ),
        .init(
            target: .transcriptionPreviewLength,
            title: AppLanguage.text("Transcription Preview Length"),
            terms: ["recent characters notch pill preview size"]
        ),
        .init(
            target: .overlayStyle,
            title: AppLanguage.text("Overlay Size & Notch Style"),
            terms: ["large compact regular recording indicator presentation layout"]
        ),
        .init(
            target: .livePreview,
            title: AppLanguage.text("Live Preview"),
            terms: ["streaming transcription text while speak overlay"]
        ),
        .init(target: .bottomOffset, title: AppLanguage.text("Bottom Offset"), terms: ["distance from bottom screen pixels position"]),

        .init(
            target: .dataAndDiagnostics,
            title: AppLanguage.text("Data & Diagnostics"),
            terms: ["backup restore debug logs storage troubleshooting"]
        ),
        .init(
            target: .backupAndRestore,
            title: AppLanguage.text("Backup & Restore"),
            terms: ["export import settings prompt profiles history stats API keys"]
        ),
        .init(
            target: .audioStorage,
            title: AppLanguage.text("Audio Storage"),
            terms: ["history budget GB export ZIP delete prune WAV manifest"]
        ),
        .init(
            target: .debugLogs,
            title: AppLanguage.text("Debug Settings"),
            terms: ["Show Debug Logs in App Reveal Log File crash diagnostics troubleshooting"]
        ),
        .init(
            target: .experimental,
            title: AppLanguage.text("Experimental"),
            terms: ["preview early access optional features"]
        ),
        .init(
            target: .historyPerformance,
            title: AppLanguage.text("Show Performance in History"),
            terms: ["timing speed tokens per second ASR cleanup"]
        ),
    ]

    static func results(for query: String) -> [SettingsSearchResult] {
        let normalizedQuery = self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let rankedResults: [(index: Int, result: SettingsSearchResult)] = self.entries.enumerated().compactMap { index, entry in
            guard let score = self.score(entry, for: normalizedQuery) else { return nil }
            return (index, SettingsSearchResult(target: entry.target, score: score))
        }

        return rankedResults.sorted { lhs, rhs in
            if lhs.result.score == rhs.result.score {
                return lhs.index < rhs.index
            }
            return lhs.result.score > rhs.result.score
        }
        .map(\.result)
        .filter { SettingsSection.productSections.contains($0.section) }
    }

    static func matchingSections(for query: String) -> [SettingsSection] {
        let matchingSections = Set(self.results(for: query).map(\.section))
        return SettingsSection.allCases.filter(matchingSections.contains)
    }

    static func preferredSection(
        current: SettingsSection?,
        results: [SettingsSearchResult]
    ) -> SettingsSection? {
        guard !results.isEmpty else { return current }
        if let current, results.contains(where: { $0.section == current }) {
            return current
        }
        return results.first?.section
    }

    private static func score(_ entry: Entry, for query: String) -> Int? {
        let fields = [
            WeightedField(text: entry.title, weight: 100),
            WeightedField(text: entry.target.section.title, weight: 45),
        ] + entry.terms.map { WeightedField(text: $0, weight: 55) }

        let allQueryTokens = self.tokens(in: query)
        let meaningfulQueryTokens = allQueryTokens.filter { !self.queryStopWords.contains($0) }
        let queryTokens = meaningfulQueryTokens.isEmpty ? allQueryTokens : meaningfulQueryTokens
        let compactQuery = self.compact(query)
        let compactCandidates = fields.flatMap { field in
            var candidates = [self.compact(self.normalize(field.text))]
            for token in self.tokens(in: field.text) {
                candidates.append(self.compact(token))
            }
            return candidates
        }
        let hasCompactFuzzyMatch = compactQuery.count >= 4 &&
            compactCandidates.contains(where: { self.isFuzzyMatch(query: compactQuery, candidate: $0) })
        var score = 0

        for queryToken in queryTokens {
            let bestTokenScore = fields.compactMap { field -> Int? in
                self.tokens(in: field.text)
                    .compactMap { self.tokenScore(query: queryToken, candidate: $0) }
                    .max()
                    .map { $0 + field.weight }
            }.max()

            if let bestTokenScore {
                score += bestTokenScore
            } else if !hasCompactFuzzyMatch {
                return nil
            }
        }

        let normalizedTitle = self.normalize(entry.title)
        let normalizedSection = self.normalize(entry.target.section.title)
        score += self.phraseBonus(query: query, candidate: normalizedTitle, exactBonus: 1000)
        score += self.phraseBonus(query: query, candidate: normalizedSection, exactBonus: 400)

        for term in entry.terms {
            score += self.phraseBonus(query: query, candidate: self.normalize(term), exactBonus: 220)
        }

        if hasCompactFuzzyMatch {
            score += 180
        }

        return score
    }

    private static func phraseBonus(query: String, candidate: String, exactBonus: Int) -> Int {
        if candidate == query {
            return exactBonus
        }
        if candidate.hasPrefix(query) {
            return exactBonus * 3 / 5
        }
        if query.count >= 3, candidate.contains(query) {
            return exactBonus * 2 / 5
        }
        return 0
    }

    private static func tokenScore(query: String, candidate: String) -> Int? {
        if candidate == query {
            return 120
        }
        if candidate.hasPrefix(query) {
            return 105
        }
        if query.count >= 3, candidate.contains(query) {
            return 90
        }
        if self.isFuzzyMatch(query: query, candidate: candidate) {
            return 70 - (self.editDistance(query, candidate) * 8)
        }
        return nil
    }

    private static func isFuzzyMatch(query: String, candidate: String) -> Bool {
        let tolerance: Int
        switch query.count {
        case 0...3:
            return false
        case 4...6:
            tolerance = 1
        default:
            tolerance = 2
        }

        guard abs(query.count - candidate.count) <= tolerance else { return false }
        return self.editDistance(query, candidate) <= tolerance
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(right.count + 1)

            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        let separated = folded.map { character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(separated)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func tokens(in value: String) -> [String] {
        self.normalize(value).split(separator: " ").map(String.init)
    }

    private static func compact(_ value: String) -> String {
        value.filter { !$0.isWhitespace }
    }
}

struct SettingsSearchField: NSViewRepresentable {
    @Binding var text: String
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.delegate = context.coordinator
        searchField.placeholderString = "Search Settings"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.controlSize = .regular
        searchField.focusRingType = .default
        searchField.setAccessibilityLabel("Search Settings")
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if searchField.stringValue != self.text {
            searchField.stringValue = self.text
        }
        Self.resignFocusIfNeeded(from: searchField, isActive: self.isActive)
    }

    static func resignFocusIfNeeded(from searchField: NSSearchField, isActive: Bool) {
        guard !isActive,
              searchField.currentEditor() != nil,
              let window = searchField.window
        else { return }

        window.makeFirstResponder(nil)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SettingsSearchField

        init(_ parent: SettingsSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            self.parent.text = searchField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            textView.string = ""
            control.stringValue = ""
            self.parent.text = ""
            return true
        }
    }
}
