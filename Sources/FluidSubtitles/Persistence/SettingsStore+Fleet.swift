import Foundation

extension SettingsStore {
    var commercialSeatID: String {
        CommercialSeat.currentID
    }

    var commercialLicenseIsManaged: Bool {
        FleetManagedDirectory.licenseToken() != nil
    }

    var commercialSeatRefusal: String? {
        guard let record = self.commercialLicenseRecord else { return nil }
        return self.seatDecision(for: record).refusalLine
    }

    func seatDecision(for record: CommercialLicense.Record) -> CommercialSeat.Decision {
        CommercialSeat.decide(
            license: record,
            rosterToken: FleetManagedDirectory.rosterToken(),
            seatID: self.commercialSeatID,
            publicKey: Self.licenseVerifyingKey
        )
    }

    func commercialCoverageLine(for record: CommercialLicense.Record) -> String {
        var line = "\(record.seats) seats. \(record.expiryLine())"
        if record.sla {
            line += " Written SLA."
        }
        if case let .accepted(count) = self.seatDecision(for: record) {
            line += " This Mac is on the seat list (\(count) of \(record.seats))."
        }
        return line
    }

    func exportFleetSettingsData() throws -> Data {
        let data = try FleetSettingsDocument.capture(from: self).encoded()
        FleetAudit.record(.settingsExported, fields: ["via": "user"])
        return data
    }

    func restoreFleetSettingsData(_ data: Data) throws {
        try FleetSettingsDocument.decode(data).apply(to: self)
        FleetAudit.record(.settingsRestored, fields: ["via": "user"])
    }

    /// MDM license and settings. A settings file applies when its bytes change.
    /// A later edit on this Mac stays until IT ships a new file.
    func applyManagedFleetIfNeeded() {
        self.noteManagedLicense()
        guard let data = FleetManagedDirectory.settingsData() else { return }
        let hash = FleetSettingsDocument.sha256Hex(data)
        if self.defaults.string(forKey: FleetBookkeeping.appliedSettingsHash) == hash { return }
        do {
            try FleetSettingsDocument.decode(data).apply(to: self)
            self.defaults.set(hash, forKey: FleetBookkeeping.appliedSettingsHash)
            FleetAudit.record(.settingsRestored, fields: ["via": "mdm"])
        } catch {
            let detail = (error as? FleetSettingsDocument.Failure)?.logDetail ?? error.localizedDescription
            DebugLogger.shared.warning(
                "Managed caption policy was not applied: \(detail)",
                source: "FleetSettings"
            )
        }
    }

    func resetManagedFleetBookkeeping() {
        self.defaults.removeObject(forKey: FleetBookkeeping.appliedSettingsHash)
        self.defaults.removeObject(forKey: FleetBookkeeping.managedLicenseHash)
    }

    func noteCommercialLicenseActivated(_ record: CommercialLicense.Record, via: String) {
        FleetAudit.record(
            .licenseActivated,
            fields: [
                "org": record.org,
                "seats": String(record.seats),
                "sla": record.sla ? "true" : "false",
                "via": via,
            ]
        )
        guard record.enforceSeats else { return }
        switch self.seatDecision(for: record) {
        case .accepted:
            FleetAudit.record(.seatAccepted, fields: ["org": record.org, "via": via])
        case let .refused(reason):
            FleetAudit.record(
                .seatRefused,
                fields: ["org": record.org, "reason": reason.rawValue, "via": via]
            )
        case .notRequired:
            break
        }
    }

    private func noteManagedLicense() {
        guard let token = FleetManagedDirectory.licenseToken() else { return }
        let hash = FleetSettingsDocument.sha256Hex(Data(token.utf8))
        if self.defaults.string(forKey: FleetBookkeeping.managedLicenseHash) == hash { return }
        self.defaults.set(hash, forKey: FleetBookkeeping.managedLicenseHash)
        guard let record = self.commercialLicenseRecord else { return }
        self.noteCommercialLicenseActivated(record, via: "mdm")
    }

    private enum FleetBookkeeping {
        static let appliedSettingsHash = "FleetSettingsAppliedHash"
        static let managedLicenseHash = "FleetManagedLicenseHash"
    }
}
