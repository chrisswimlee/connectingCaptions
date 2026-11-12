import ConnectingCaptionsCore
import FluidAudio
import SwiftUI

struct ProIOSHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: ProIOSSession
    @EnvironmentObject private var license: ProIOSLicenseStore
    @EnvironmentObject private var settings: ProIOSSettings
    @State private var showLicense = false
    @State private var showAdjust = false
    @State private var confirmClear = false
    @State private var inputs: [ProIOSInput] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(ConnectingCaptionsProduct.displayName)
                    .font(.title2.weight(.bold))
                    .lineLimit(nil)
                self.languages
                self.enginePicker
                self.listenControls
                self.packButton
                self.tools
                Text(self.session.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(self.session.status)
                self.board
                self.tail
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(ConnectingCaptionsProduct.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Adjust") { self.showAdjust = true }
                        .accessibilityLabel("Adjust")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("License") { self.showLicense = true }
                        .accessibilityLabel("License")
                }
            }
            .sheet(isPresented: self.$showAdjust) {
                ProIOSAdjustView(inputs: self.inputs)
                    .environmentObject(self.settings)
            }
            .sheet(isPresented: self.$showLicense) {
                ProIOSLicenseView()
                    .environmentObject(self.license)
            }
            .background {
                ProIOSTranslationHost(engine: self.session.translator)
            }
            .onAppear {
                self.inputs = (try? ProIOSMicrophone.inputs()) ?? []
            }
            .onChange(of: self.session.source) { _, source in
                self.session.translator.prepare(source: source, target: self.session.target)
            }
            .onChange(of: self.session.target) { _, target in
                self.session.translator.prepare(source: self.session.source, target: target)
            }
            .onChange(of: self.settings.engine) { _, engine in
                self.session.selectEngine(engine)
            }
            .onChange(of: self.scenePhase) { _, phase in
                // No Float on this build. Leaving the app stops Listen, the
                // same as the App Store app when Float is off.
                guard phase == .background else { return }
                Task { await self.session.stop() }
            }
        }
    }

    private var languages: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("I speak")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("I speak", selection: self.$session.source) {
                ForEach(TranslationLanguageCatalog.menuOrder) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .disabled(self.session.isListening || self.session.isStarting)
            Text("Show as")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Show as", selection: self.$session.target) {
                ForEach(TranslationLanguageCatalog.menuOrder) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .disabled(self.session.isListening || self.session.isStarting)
        }
    }

    private var enginePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice engine")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Voice engine", selection: self.$settings.engine) {
                ForEach(StreamingModelVariant.allCases, id: \.self) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .disabled(self.session.isListening || self.session.isStarting)
            Text("FluidVoice on this iPhone or iPad. Connecting Captions, on the Mac App Store, is the smaller Apple Speech board.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var listenControls: some View {
        HStack(spacing: 12) {
            Button(action: self.session.toggleListen) {
                Text(self.session.isListening || self.session.isStarting ? "Stop" : "Listen")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(self.session.isListening || self.session.isStarting ? "Stop" : "Listen")
            .accessibilityHint(self.session.isStarting ? "Stops preparing the microphone." : "")
            if self.session.isListening {
                Button(action: self.session.togglePause) {
                    Text(self.session.isPaused ? "Resume" : "Pause")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(self.session.isPaused ? "Resume" : "Pause")
            }
        }
    }

    private var tools: some View {
        HStack(spacing: 12) {
            Button("Undo", action: self.session.undo)
                .frame(minHeight: 44)
                .accessibilityLabel("Undo last caption")
            Button("Copy", action: self.session.copyBoard)
                .frame(minHeight: 44)
                .accessibilityLabel("Copy captions")
            Button("Clear") {
                self.confirmClear = true
            }
            .frame(minHeight: 44)
            .disabled(self.session.board.rows.isEmpty)
            .accessibilityLabel("Clear captions")
        }
        .buttonStyle(.bordered)
        .confirmationDialog(
            "Clear captions?",
            isPresented: self.$confirmClear,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                self.session.clearBoard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every caption. The microphone stays on.")
        }
    }

    @ViewBuilder
    private var packButton: some View {
        if self.session.translator.packStatus == .needsDownload {
            Button("Download language pack") {
                Task { await self.session.translator.downloadPack() }
            }
            .frame(minHeight: 44)
        }
    }

    private var board: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if self.session.board.rows.isEmpty {
                        Text(self.session.isListening ? "Listening" : "Each sentence appears when it is ready.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(self.session.board.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.translated.isEmpty ? row.source : row.translated)
                                .font(.system(size: self.settings.captionSize, weight: .semibold))
                            if self.settings.spokenLine, row.source != row.translated, !row.translated.isEmpty {
                                Text(row.source)
                                    .font(.system(size: max(16, self.settings.captionSize * 0.65)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(row.id)
                    }
                }
            }
            .onChange(of: self.session.board.lineIDs) { _, ids in
                if let last = ids.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
                if let text = self.session.board.rows.last?.translated, !text.isEmpty {
                    AccessibilityNotification.Announcement(text).post()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theater captions")
    }

    private var tail: some View {
        Text(self.session.openTail.isEmpty ? " " : self.session.openTail)
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(self.session.openTail.isEmpty ? "Waiting for the next sentence" : self.session.openTail)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct ProIOSTranslationHost: View {
    @ObservedObject var engine: ProIOSTranslation

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .translationTask(self.engine.configuration) { session in
                await self.engine.use(session)
            }
    }
}

struct ProIOSLicenseView: View {
    @EnvironmentObject private var license: ProIOSLicenseStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(self.license.statusTitle)
                        .font(.headline)
                    Text(self.license.statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("License key", text: self.$draft, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("License key")
                    Button("Save license key") {
                        self.license.save(token: self.draft)
                    }
                    .frame(minHeight: 44)
                    if self.license.record != nil || self.license.hasStoredToken {
                        Button("Remove license key", role: .destructive) {
                            self.license.removeLicense()
                        }
                        .frame(minHeight: 44)
                    }
                } footer: {
                    Text("Speech recognition is FluidVoice by altic-dev, GPLv3. The model downloads to this device the first time you listen. Audio and captions stay here.")
                }
                if let message = self.license.statusMessage, !message.isEmpty {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("License")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { self.dismiss() }
                }
            }
        }
    }
}

private struct ProIOSAdjustView: View {
    @EnvironmentObject private var settings: ProIOSSettings
    @Environment(\.dismiss) private var dismiss
    let inputs: [ProIOSInput]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show the original line", isOn: self.$settings.spokenLine)
                    Toggle("Read captions aloud", isOn: self.$settings.speakCaptions)
                    LabeledContent("Size", value: "\(Int(self.settings.captionSize))")
                    Slider(value: self.$settings.captionSize, in: 18...64, step: 2) {
                        Text("Caption size")
                    }
                    .accessibilityLabel("Caption size")
                } footer: {
                    Text("Read captions aloud speaks each Show as line. The same language stays quiet.")
                }
                if self.inputs.count > 1 {
                    Section("Microphone") {
                        Picker("Input", selection: self.$settings.inputUID) {
                            Text("System").tag(String?.none)
                            ForEach(self.inputs) { input in
                                Text(input.name).tag(Optional(input.uid))
                            }
                        }
                    }
                }
                Section {
                    Text("Turn on the Connecting Captions Pro keyboard in Settings → General → Keyboard. Allow Full Access so it can insert the last caption. It cannot use the microphone.")
                        .font(.caption)
                }
            }
            .navigationTitle("Adjust")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { self.dismiss() }
                }
            }
        }
    }
}
