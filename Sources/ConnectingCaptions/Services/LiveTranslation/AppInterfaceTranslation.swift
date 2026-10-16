import Combine
import Foundation
import SwiftUI
import Translation

/// Translates only the bundled interface catalog. Separate from the caption
/// mailbox: changing app language cannot retarget an in-flight caption.
final class AppInterfaceTranslation: ObservableObject, @unchecked Sendable {
    static let shared = AppInterfaceTranslation()
    @Published private(set) var revision = 0
    @Published private(set) var errorDescription: String?
    @Published private(set) var retryGeneration = 0
    private var translations: [String: [String: String]] = [:]
    /// Keyed by languageID, invalidated by `revision` — a settings re-render
    /// must not re-scan and re-sort the ~1,100-entry catalog every time.
    private var missingStringsCache: [String: (revision: Int, result: [String])] = [:]
    private let lock = NSLock()
    private let cacheURL: URL?
    private static let markerPattern = try? NSRegularExpression(pattern: "\\{[0-9]+\\}")

    init(cacheURL: URL? = nil, loadsCache: Bool = true) {
        self.cacheURL = cacheURL ?? (SettingsStore.isRunningTests ? nil : AppSupportDirectory.url()
            .appendingPathComponent("InterfaceTranslations.json"))
        if loadsCache, let url = self.cacheURL,
           let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            self.translations = saved.filter { TranslationLanguageCatalog.supportedIDs.contains($0.key) }.mapValues { values in
                values.filter { AppInterfaceCatalog.strings.contains($0.key) && Self.isUsable($0.value, for: $0.key) }
            }
        }
    }

    func text(_ english: String, languageID: String) -> String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard AppInterfaceCatalog.strings.contains(english),
              let translated = self.translations[languageID]?[english]
        else { return nil }
        return translated
    }

    func missingStrings(languageID: String) -> [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let cached = self.missingStringsCache[languageID], cached.revision == self.revision {
            return cached.result
        }
        let translated = self.translations[languageID] ?? [:]
        let result = AppInterfaceCatalog.strings.filter { translated[$0] == nil }.sorted()
        self.missingStringsCache[languageID] = (self.revision, result)
        return result
    }

    @MainActor
    func retry() {
        self.errorDescription = nil
        self.retryGeneration += 1
    }

    @MainActor
    func accept(_ values: [String: String], languageID: String) {
        guard TranslationLanguageCatalog.supportedIDs.contains(languageID), languageID != "en" else { return }
        let valid = values.filter {
            AppInterfaceCatalog.strings.contains($0.key) && Self.isUsable($0.value, for: $0.key)
        }
        guard !valid.isEmpty else { return }
        let snapshot = self.lock.withLock {
            self.translations[languageID, default: [:]].merge(valid) { _, new in new }
            return self.translations
        }
        self.errorDescription = nil
        self.revision += 1
        if let url = self.cacheURL {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            } catch {
                self.errorDescription = error.localizedDescription
            }
        }
    }

    static func isUsable(_ translated: String, for source: String) -> Bool {
        guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        func markers(_ text: String) -> [String] {
            let range = NSRange(text.startIndex..., in: text)
            return (Self.markerPattern?.matches(in: text, range: range) ?? []).map {
                (text as NSString).substring(with: $0.range)
            }.sorted()
        }
        return markers(source) == markers(translated)
    }

    @MainActor
    func translate(using session: TranslationSession, languageID: String) async {
        let missing = self.missingStrings(languageID: languageID)
        guard !missing.isEmpty else { return }
        do {
            try await session.prepareTranslation()
            for start in stride(from: 0, to: missing.count, by: 24) {
                try Task.checkCancellation()
                let batch = missing[start..<min(start + 24, missing.count)].map {
                    TranslationSession.Request(sourceText: $0, clientIdentifier: $0)
                }
                let responses = try await session.translations(from: batch)
                try Task.checkCancellation()
                var translated: [String: String] = [:]
                for response in responses {
                    if let source = response.clientIdentifier { translated[source] = response.targetText }
                }
                self.accept(translated, languageID: languageID)
            }
            if !self.missingStrings(languageID: languageID).isEmpty {
                self.errorDescription = AppLanguage.text("Some interface labels could not be translated. English remains available; you can retry.")
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.errorDescription = error.localizedDescription
        }
    }
}

/// Observes cache updates at each interface label. Caption strings continue to
/// use ordinary Text and never enter the catalog or translation session.
struct AppText: View {
    @ObservedObject private var translations = AppInterfaceTranslation.shared
    @ObservedObject private var settings = SettingsStore.shared
    let value: String
    var arguments: [String] = []

    init(_ value: String) { self.value = value }
    init(_ value: String, arguments: [String]) {
        self.value = value
        self.arguments = arguments
    }

    var body: some View { Text(AppLanguage.format(self.value, arguments: self.arguments)) }
}

struct AppButton: View {
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View { Button(role: self.role, action: self.action) { AppText(self.title) } }
}

struct AppLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View { Label { AppText(self.title) } icon: { Image(systemName: self.systemImage) } }
}

struct AppToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View { Toggle(isOn: self.$isOn) { AppText(self.title) } }
}

struct AppInterfaceTranslationHost: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var translations = AppInterfaceTranslation.shared
    @ObservedObject private var captions = LiveTranslationController.shared
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: "\(self.settings.appLanguageID)-\(self.translations.retryGeneration)-\(self.captions.isSessionActive)") {
                let id = self.settings.appLanguageID
                var next: TranslationSession.Configuration? = id == "en" || SettingsStore.isRunningTests || self.captions.isSessionActive
                    || self.translations.missingStrings(languageID: id).isEmpty ? nil
                    : AppleTranslationStrategy.makeLowLatencyConfiguration(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: id))
                if next == self.configuration { next?.invalidate() }
                self.configuration = next
            }
            .translationTask(self.configuration) { session in
                let id = session.targetLanguage?.languageCode?.identifier ?? "en"
                await self.translations.translate(using: session, languageID: id)
            }
            .onChange(of: self.translations.revision) { _, _ in
                // Refresh help, menu titles, and accessibility copy as well as labels.
                SettingsStore.shared.objectWillChange.send()
            }
            .accessibilityHidden(true)
    }
}

struct AppInterfaceLanguageSettings: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var translations = AppInterfaceTranslation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: Binding(
                get: { self.settings.appLanguageID },
                set: { self.settings.appLanguageID = $0 }
            )) {
                ForEach(TranslationLanguageCatalog.all) { language in
                    Text(AppLanguage.localizedName(for: language, languageID: language.id)).tag(language.id)
                }
            } label: { AppText("App language") }
            AppText("Interface translations run on this Mac. Apple may ask to download a language pack. English stays available while it prepares.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if self.settings.appLanguageID != "en" {
                if let error = self.translations.errorDescription {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    AppButton("Retry interface translation") { self.translations.retry() }
                } else if !self.translations.missingStrings(languageID: self.settings.appLanguageID).isEmpty {
                    ProgressView { AppText("Preparing interface translation…") }
                        .controlSize(.small)
                }
            }
        }
    }
}
