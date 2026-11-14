//
//  SettingsView+Controls.swift
//  fluid
//
//  Flow layout and dictionary suggestion row.
//

import SwiftUI

// MARK: - Flow Layout

struct FlowLayout: Layout {
    struct Cache {
        var sizes: [CGSize] = []
        var positions: [CGPoint] = []
        var containerSize: CGSize = .zero
        var lastWidth: CGFloat = 0
    }

    var spacing: CGFloat = 8

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: Array(repeating: .zero, count: subviews.count))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        self.arrangeSubviews(proposal: proposal, subviews: subviews, cache: &cache)
        return cache.containerSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        self.arrangeSubviews(proposal: proposal, subviews: subviews, cache: &cache)
        for (index, position) in cache.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let proposedWidth = proposal.width ?? 0
        let maxWidth = proposedWidth > 0 ? proposedWidth : 260
        let needsLayout = cache.positions.count != subviews.count || cache.lastWidth != maxWidth

        if needsLayout {
            cache.positions = []
            cache.positions.reserveCapacity(subviews.count)
            cache.sizes = Array(repeating: .zero, count: subviews.count)
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for index in subviews.indices {
            let size: CGSize
            if needsLayout {
                size = subviews[index].sizeThatFits(.unspecified)
                cache.sizes[index] = size
            } else {
                size = cache.sizes[index]
            }

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + self.spacing
                rowHeight = 0
            }
            if needsLayout {
                cache.positions.append(CGPoint(x: x, y: y))
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + self.spacing
        }

        cache.containerSize = CGSize(width: maxWidth, height: y + rowHeight)
        cache.lastWidth = maxWidth
    }
}

extension SettingsView {
    var spokenSendSettings: some View {
        Group {
            self.optionToggleRow(
                title: AppLanguage.text("Spoken Send"),
                description: AppLanguage.text("Say a phrase at the end of dictation to send with your chosen Enter command."),
                isOn: Binding(
                    get: { self.settings.spokenSendEnabled },
                    set: { self.settings.spokenSendEnabled = $0 }
                )
            )

            if self.settings.spokenSendEnabled {
                VStack(spacing: 10) {
                    self.optionToggleRow(
                        title: AppLanguage.text("Send Immediately"),
                        description: AppLanguage.text("Stop listening and send as soon as the phrase is recognized. May not work with all voice models; Parakeet is recommended."),
                        isOn: Binding(
                            get: { self.settings.spokenSendImmediatelyEnabled },
                            set: { self.settings.spokenSendImmediatelyEnabled = $0 }
                        )
                    )

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            AppText("Send Phrase")
                                .font(self.theme.typography.bodyStrong)
                                .foregroundStyle(self.settingsTitleText)
                            AppText("Say it at the end. Say “literal {0}” to dictate it normally.", arguments: [String(describing: self.settings.spokenSendPhrase)])
                                .font(self.theme.typography.bodySmall)
                                .foregroundStyle(self.settingsSecondaryText)
                        }

                        Spacer()

                        TextField(
                            AppLanguage.text("send it"),
                            text: Binding(
                                get: { self.settings.spokenSendPhrase },
                                set: { self.settings.spokenSendPhrase = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .accessibilityLabel(AppLanguage.text("Spoken Send phrase"))
                    }

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            AppText("Send Command")
                                .font(self.theme.typography.bodyStrong)
                                .foregroundStyle(self.settingsTitleText)
                            AppText("Choose the Enter behavior expected by the destination app.")
                                .font(self.theme.typography.bodySmall)
                                .foregroundStyle(self.settingsSecondaryText)
                        }

                        Spacer()

                        Picker("", selection: Binding(
                            get: { self.settings.spokenSendKey },
                            set: { self.settings.spokenSendKey = $0 }
                        )) {
                            ForEach(SettingsStore.SpokenSendKey.allCases) { key in
                                AppText(key.displayName).tag(key)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 170, alignment: .trailing)
                        .accessibilityLabel(AppLanguage.text("Spoken Send command"))
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}

struct DictionarySuggestionsSettingsRow: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                AppText("Auto-Learn Corrections")
                    .font(self.theme.typography.bodyStrong)
                    .foregroundStyle(self.theme.palette.primaryText)
                AppText("Suggest saving words after you correct dictated text.")
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker(AppLanguage.text("Suggest after"), selection: self.$settings.automaticDictionarySuggestionFrequency) {
                ForEach(SettingsStore.AutomaticDictionarySuggestionFrequency.allCases) { frequency in
                    AppText(frequency.displayName).tag(frequency)
                }
            }
            .labelsHidden()
            .frame(width: 138)
            .disabled(!self.settings.automaticDictionaryLearningEnabled)

            Toggle("", isOn: Binding(
                get: { self.settings.automaticDictionaryLearningEnabled },
                set: { enabled in
                    self.settings.automaticDictionaryLearningEnabled = enabled
                    if !enabled {
                        AutomaticDictionaryCorrectionTracker.shared.cancel()
                    }
                }
            ))
            .toggleStyle(.switch)
            .tint(self.theme.palette.accent)
            .labelsHidden()
        }
    }
}
