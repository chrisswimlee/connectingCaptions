import AppKit
import Combine
import SwiftUI

@MainActor
final class VoiceEngineSettingsViewModel: ObservableObject {
    let settings: SettingsStore
    private let appServices: AppServices
    private var cancellables = Set<AnyCancellable>()

    var asr: ASRService { self.appServices.asr }

    var areSpeechModelActionsBlocked: Bool {
        self.asr.isRunning
            || self.downloadingModel != nil
            || self.asr.hasActiveModelDownload
            || self.asr.hasActiveModelPreparation
            || self.asr.isCancellingModelPreparation
            || (!self.asr.isAsrReady && (self.asr.isDownloadingModel || self.asr.isLoadingModel))
    }

    @Published var selectedSpeechProvider: SettingsStore.SpeechModel.Provider
    @Published var previewSpeechModel: SettingsStore.SpeechModel
    @Published var suppressSpeechProviderSync: Bool = false
    @Published var skipNextSpeechModelSync: Bool = false

    var downloadingModel: SettingsStore.SpeechModel? {
        guard let modelID = self.asr.downloadingModelId else { return nil }
        return SettingsStore.SpeechModel.allCases.first { $0.id == modelID }
    }

    var downloadProgress: Double {
        self.asr.downloadProgress ?? 0.0
    }

    var isCancellingModelDownload: Bool {
        self.asr.isCancellingModelDownload
    }

    init(settings: SettingsStore, appServices: AppServices) {
        self.settings = settings
        self.appServices = appServices
        self.previewSpeechModel = settings.selectedSpeechModel
        self.selectedSpeechProvider = settings.selectedSpeechModel.provider
        appServices.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &self.cancellables)
    }

    func onAppear() {
        if SpokenLanguageResolver.syncSpokenEngineToTheater(settings: self.settings),
           !self.asr.isRunningOrStarting
        {
            self.asr.resetTranscriptionProvider()
        }
        self.previewSpeechModel = self.settings.selectedSpeechModel
        self.selectedSpeechProvider = self.settings.selectedSpeechModel.provider

        Task {
            await self.asr.checkIfModelsExistAsync()
        }
        Task {
            await AppleSpeechLiveCapability.refreshAnalyzer()
            self.objectWillChange.send()
        }
    }

    func handleSelectedSpeechModelChange(_ newValue: SettingsStore.SpeechModel) {
        if self.skipNextSpeechModelSync {
            self.skipNextSpeechModelSync = false
            return
        }
        guard !self.suppressSpeechProviderSync else { return }
        self.previewSpeechModel = newValue
        self.setSelectedSpeechProvider(newValue.provider)
    }

    func activateSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.areSpeechModelActionsBlocked else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            self.settings.selectedSpeechModel = model
            self.previewSpeechModel = model
            self.setSelectedSpeechProvider(model.provider)
        }
        SpokenLanguageResolver.pinSpokenEngineToSource(settings: self.settings)
        self.asr.resetTranscriptionProvider()
        Task {
            do {
                try await self.asr.ensureAsrReady()
            } catch is CancellationError {
                DebugLogger.shared.info("Model activation cancelled: \(model.displayName)", source: "AISettingsView")
            } catch {
                DebugLogger.shared.error("Failed to prepare model after activation: \(error)", source: "AISettingsView")
                self.asr.errorTitle = "Model Activation Failed"
                self.asr.errorMessage = error.localizedDescription
                self.asr.showError = true
            }
        }
    }

    func downloadSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.areSpeechModelActionsBlocked else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.asr.downloadModel(model, progressHandler: nil)
                DebugLogger.shared.info("Model download completed: \(model.displayName)", source: "VoiceEngineVM")
            } catch is CancellationError {
                DebugLogger.shared.info("Model download cancelled: \(model.displayName)", source: "VoiceEngineVM")
            } catch {
                DebugLogger.shared.error("Failed to download model \(model.displayName): \(error)", source: "VoiceEngineVM")
                self.asr.errorTitle = "Model Download Failed"
                self.asr.errorMessage = error.localizedDescription
                self.asr.showError = true
            }
        }
    }

    /// Model currently running a raw mic → ASR test (see `testSpeechModel`), or nil.
    @Published private(set) var testingModel: SettingsStore.SpeechModel?
    /// Which row `testResultText`/`testErrorText` belongs to, so the result renders
    /// under the model that was actually tested, not whichever is active now.
    @Published private(set) var lastTestedModel: SettingsStore.SpeechModel?
    @Published private(set) var testResultText: String?
    @Published private(set) var testErrorText: String?
    private var testTask: Task<Void, Never>?

    /// Records a few seconds and shows the raw transcribed text (or the real thrown
    /// error) for `model`, bypassing Theater's session/board/translation machinery
    /// entirely — a direct mic → ASR round trip, same `start()`/`stop()` Theater
    /// Listen uses, so errors surface here instead of only in the debug log.
    func testSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard self.testingModel == nil, !self.areSpeechModelActionsBlocked else { return }
        let previousActive = self.settings.selectedSpeechModel
        let shouldRestore = previousActive != model
        self.testingModel = model
        self.lastTestedModel = model
        self.testResultText = nil
        self.testErrorText = nil
        self.testTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    if shouldRestore {
                        self.skipNextSpeechModelSync = true
                        self.settings.selectedSpeechModel = previousActive
                        self.asr.resetTranscriptionProvider()
                        self.suppressSpeechProviderSync = false
                    }
                    self.testingModel = nil
                }
            }
            if shouldRestore {
                self.suppressSpeechProviderSync = true
                self.settings.selectedSpeechModel = model
                self.asr.resetTranscriptionProvider()
            }
            let granted = await MicrophoneAccess.authorize(updating: self.asr)
            guard granted else {
                self.testErrorText = MicrophoneAccess.failureCopy(detail: self.asr.microphoneAccessDetail)
                return
            }
            do {
                try await self.asr.ensureAsrReady()
            } catch {
                if !(error is CancellationError) {
                    self.testErrorText = error.localizedDescription
                }
                return
            }
            guard await self.asr.start() != .failed else {
                self.testErrorText = "Could not start listening. Check the microphone."
                return
            }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            let text = await self.asr.stop(onFinalTranscriptionStarted: nil)
            guard !Task.isCancelled else { return }
            self.testResultText = text.isEmpty ? "No speech detected." : text
        }
    }

    /// Ends the test early; whatever was captured so far still gets transcribed.
    func cancelSpeechModelTest() {
        self.testTask?.cancel()
    }

    func cancelSpeechModelDownload() {
        guard self.downloadingModel != nil, !self.isCancellingModelDownload else { return }
        self.asr.cancelModelDownload()
    }

    func cancelActiveModelPreparation() {
        self.asr.cancelModelPreparation()
    }

    func deleteSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.areSpeechModelActionsBlocked else { return }
        let previousActive = self.settings.selectedSpeechModel

        Task {
            let shouldRestore = previousActive != model
            await MainActor.run {
                if shouldRestore {
                    self.suppressSpeechProviderSync = true
                }
                self.settings.selectedSpeechModel = model
                self.asr.resetTranscriptionProvider()
            }

            defer {
                Task { @MainActor in
                    guard shouldRestore else { return }
                    self.skipNextSpeechModelSync = true
                    self.settings.selectedSpeechModel = previousActive
                    self.asr.resetTranscriptionProvider()
                    if self.previewSpeechModel == model {
                        self.previewSpeechModel = model
                    }
                    self.suppressSpeechProviderSync = false
                }
            }

            await self.deleteModels()
        }
    }

    func isActiveSpeechModel(_ model: SettingsStore.SpeechModel) -> Bool {
        self.settings.selectedSpeechModel == model
    }

    func deleteModels() async {
        do {
            try await self.asr.clearModelCache()
            let model = self.settings.selectedSpeechModel
            if model.requiresExternalArtifacts {
                self.settings.setExternalCoreMLArtifactsDirectory(nil, for: model)
                self.asr.resetTranscriptionProvider()
            }
        } catch {
            DebugLogger.shared.error("Failed to delete models: \(error)", source: "AISettingsView")
        }
    }

    func setSelectedSpeechProvider(_ provider: SettingsStore.SpeechModel.Provider) {
        self.selectedSpeechProvider = provider
    }

    func openExternalModelSource(for model: SettingsStore.SpeechModel) {
        guard let url = model.externalCoreMLSpec?.sourceURL else { return }
        NSWorkspace.shared.open(url)
    }
}
