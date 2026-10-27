import Foundation

/// Listen starts during a 14-day trial, or with a key that covers this Mac.
/// The clock is the UTC day of the first Listen. A Listen already running is left alone.
nonisolated enum ListenAccess {
    enum Phase: Equatable, Sendable {
        case notStarted
        case inTrial(daysRemaining: Int)
        case ended
    }

    static func phase(startedOn: Date?, now: Date) -> Phase {
        guard let startedOn else { return .notStarted }
        let elapsed = self.elapsedUTCDays(from: startedOn, to: now)
        let remaining = ConnectingCaptionsProduct.listenTrialDays - elapsed
        if remaining <= 0 { return .ended }
        return .inTrial(daysRemaining: remaining)
    }

    static func elapsedUTCDays(from start: Date, to now: Date) -> Int {
        let startDay = CommercialLicense.day(from: CommercialLicense.dayString(start)) ?? start
        let nowDay = CommercialLicense.day(from: CommercialLicense.dayString(now)) ?? now
        let seconds = nowDay.timeIntervalSince(startDay)
        return max(0, Int(seconds / 86_400))
    }

    static var trialEndedMessage: String {
        "The 14-day trial has ended. A personal license is \(ConnectingCaptionsProduct.personalLicensePriceLine) for up to two Macs you own. Paste the key in Settings."
    }

    static func trialDetail(for phase: Phase) -> String {
        switch phase {
        case .notStarted:
            return "14 days from the first Listen. Then \(ConnectingCaptionsProduct.personalLicensePriceLine) for up to two Macs you own."
        case let .inTrial(daysRemaining):
            if daysRemaining == 1 {
                return "1 day left in the trial."
            }
            return "\(daysRemaining) days left in the trial."
        case .ended:
            return self.trialEndedMessage
        }
    }
}
