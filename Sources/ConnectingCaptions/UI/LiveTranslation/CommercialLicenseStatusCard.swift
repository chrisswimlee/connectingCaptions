import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Optional work notice, or Licensed to {org} after a signed key.
struct CommercialLicenseStatusCard: View {
    var showsKeyField = false
    var compact = false
    var style: ThemedCardStyle = .standard

    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @State private var draft = ""
    @State private var message: String?
    @State private var confirmClearAudit = false

    var body: some View {
        if self.compact {
            self.compactBody
        } else {
            self.fullBody
        }
    }

    private var compactBody: some View {
        HStack(spacing: 8) {
            Text(self.compactStatus)
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if self.showsLicenseRequest {
                Link(AppLanguage.text("Email to buy"), destination: ConnectingCaptionsProduct.commercialLicenseMailURL)
                    .textLinkPointer()
                    .font(self.theme.typography.bodySmall)
                    .accessibilityIdentifier("commercial.license.request")
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("commercial.license")
    }

    private var fullBody: some View {
        ThemedCard(style: self.style, hoverEffect: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        AppText(self.title)
                            .font(self.theme.typography.bodyStrong)
                        Text(self.detail)
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }

                if self.showsLicenseRequest {
                    VStack(alignment: .leading, spacing: 4) {
                        AppText("Personal license {0} for up to two Macs you own.", arguments: [String(describing: ConnectingCaptionsProduct.personalLicensePriceLine)])
                        AppText("Named license {0}, {1} Macs minimum.", arguments: [String(describing: ConnectingCaptionsProduct.commercialSeatPriceLine), String(describing: ConnectingCaptionsProduct.commercialSeatMinimum)])
                        AppText("Written SLA {0}.", arguments: [String(describing: ConnectingCaptionsProduct.commercialSLAPriceLine)])
                        AppText("MDM / Jamf pkg {0}.", arguments: [String(describing: ConnectingCaptionsProduct.commercialMDMPriceLine)])
                    }
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .accessibilityIdentifier("commercial.license.prices")

                    HStack(spacing: 8) {
                        Link(AppLanguage.text("Buy a personal key"), destination: ConnectingCaptionsProduct.personalPurchaseURL)
                            .textLinkPointer()
                            .accessibilityIdentifier("commercial.license.buy")
                        Link(AppLanguage.text("Email to buy"), destination: ConnectingCaptionsProduct.commercialLicenseMailURL)
                            .textLinkPointer()
                            .accessibilityIdentifier("commercial.license.request")
                        Link(AppLanguage.text("License page"), destination: ConnectingCaptionsProduct.commercialLicenseURL)
                            .textLinkPointer()
                            .accessibilityIdentifier("commercial.license.page")
                    }
                    .font(self.theme.typography.bodySmall)
                }

                if self.showsKeyField {
                    Divider().opacity(0.3)
                    self.seatLine
                    self.keyField
                if let record = self.settings.commercialLicenseRecord, !record.personal {
                    self.fleetActions
                }
                }
            }
        }
        .accessibilityIdentifier("commercial.license")
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            AppLanguage.text("Clear the activity log on this Mac?"),
            isPresented: self.$confirmClearAudit,
            titleVisibility: .visible
        ) {
            AppButton("Clear activity log", role: .destructive) {
                FleetAudit.clear()
            }
            AppButton("Cancel", role: .cancel) {}
        } message: {
            AppText("The log stays on this Mac until you clear it. Captions are not in it.")
        }
    }

    private var showsLicenseRequest: Bool {
        !self.settings.isCommerciallyLicensed && self.settings.commercialLicenseRecord == nil
    }

    private var compactStatus: String {
        if self.settings.isCommerciallyLicensed {
            return self.title
        }
        if self.settings.commercialLicenseRecord != nil {
            let refusal = self.settings.commercialSeatRefusal
                ?? "This Mac is outside the seat list. Listen stays off until the seat list includes it."
            return "\(refusal) Send Seat ID \(self.settings.commercialSeatID) to IT."
        }
        return self.detail
    }

    private var title: String {
        if let record = self.settings.commercialLicenseRecord, self.settings.isCommerciallyLicensed {
            return record.coverageTitle
        }
        if self.settings.commercialLicenseRecord != nil {
            return "Seat list"
        }
        switch self.settings.listenTrialPhase {
        case .notStarted, .inTrial:
            return ConnectingCaptionsProduct.workNoticeTitle
        case .ended:
            return "Trial ended"
        }
    }

    private var detail: String {
        if let record = self.settings.commercialLicenseRecord {
            if self.settings.isCommerciallyLicensed {
                return self.settings.commercialCoverageLine(for: record)
            }
            if let refusal = self.settings.commercialSeatRefusal {
                return refusal
            }
        }
        if let failure = self.settings.commercialLicenseFailure {
            return failure.localizedDescription
        }
        return ListenAccess.trialDetail(for: self.settings.listenTrialPhase)
    }

    private var seatLine: some View {
        AppText("Seat ID {0}. Give this to IT if they ask which Mac this is.", arguments: [String(describing: self.settings.commercialSeatID)])
            .font(self.theme.typography.caption)
            .foregroundStyle(self.theme.palette.secondaryText)
            .textSelection(.enabled)
            .accessibilityIdentifier("commercial.seat.id")
    }

    @ViewBuilder
    private var keyField: some View {
        if self.settings.commercialLicenseIsManaged {
            AppText("Installed for this Mac.")
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(self.theme.palette.secondaryText)
        } else if self.canRemoveLicense {
            AppButton("Remove license") {
                self.settings.removeCommercialLicense()
                self.draft = ""
                self.message = nil
            }
            .buttonStyle(.theaterTextDestructive)
            .accessibilityIdentifier("commercial.license.remove")
        } else {
            TextField(AppLanguage.text("Paste a license key"), text: self.$draft)
                .textFieldStyle(.roundedBorder)
                .font(self.theme.typography.bodySmall)
                .accessibilityIdentifier("commercial.license.field")
                .onChange(of: self.draft) { _, _ in
                    self.message = nil
                }
            HStack(spacing: 8) {
                AppButton("Activate") {
                    self.activate()
                }
                .buttonStyle(.theaterTextProminent)
                .disabled(self.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("commercial.license.activate")
            }
            if let message {
                AppText(message)
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theme.palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("commercial.license.error")
            }
        }
    }

    private var canRemoveLicense: Bool {
        self.settings.commercialLicenseToken != nil && self.settings.commercialLicenseFailure == nil
    }

    private var fleetActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppButton("Export caption policy") {
                    self.exportSettings()
                }
                .buttonStyle(.theaterText)
                .accessibilityIdentifier("commercial.fleet.export")
                AppButton("Restore caption policy") {
                    self.restoreSettings()
                }
                .buttonStyle(.theaterText)
                .accessibilityIdentifier("commercial.fleet.restore")
            }
            HStack(spacing: 8) {
                AppButton("Export activity log") {
                    self.exportAudit()
                }
                .buttonStyle(.theaterText)
                .accessibilityIdentifier("commercial.audit.export")
                AppButton("Clear activity log") {
                    self.confirmClearAudit = true
                }
                .buttonStyle(.theaterTextDestructive)
                .disabled(FleetAudit.eventCount() == 0)
                .accessibilityIdentifier("commercial.audit.clear")
            }
            if let message {
                AppText(message)
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theme.palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func exportSettings() {
        do {
            try self.save(self.settings.exportFleetSettingsData(), name: "caption-policy.json")
        } catch {
            self.message = self.policyMessage(for: error)
        }
    }

    private func restoreSettings() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "Replace I speak, Show as, and caption look on this Mac?"
        alert.informativeText = "Talks and notes stay."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try self.settings.restoreFleetSettingsData(Data(contentsOf: url))
            self.message = nil
        } catch {
            self.message = self.policyMessage(for: error)
        }
    }

    private func policyMessage(for error: Error) -> String {
        if let failure = error as? FleetSettingsDocument.Failure {
            DebugLogger.shared.warning(
                "Caption policy was not used: \(failure.logDetail)",
                source: "FleetSettings"
            )
        }
        return error.localizedDescription
    }

    private func exportAudit() {
        do {
            try self.save(FleetAudit.exportData(), name: "activity-log.json")
        } catch {
            if let failure = error as? FleetAudit.Failure {
                DebugLogger.shared.warning("Activity log export: \(failure.logDetail)", source: "FleetAudit")
            }
            self.message = error.localizedDescription
        }
    }

    private func save(_ data: Data, name: String) throws {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
        self.message = nil
    }

    private func activate() {
        switch self.settings.activateCommercialLicense(self.draft) {
        case .success:
            self.draft = ""
            self.message = nil
        case let .failure(failure):
            self.message = failure.localizedDescription
        }
    }
}
