import Foundation

/// Clock math for a 14-day trial. Release 1.6.16 does not apply it:
/// Listen starts without a key. `releaseAsksForKey` is the switch.
/// The clock is the UTC day of the first Listen. A Listen already running is left alone.
nonisolated enum ListenAccess {
    /// The published direct download does not ask for a key. Same switch as iPhone and iPad Pro.
    static let releaseAsksForKey = ConnectingCaptionsProduct.directDownloadAsksForKey
    enum Phase: Equatable, Sendable {
        case notStarted
        case inTrial(daysRemaining: Int)
        case ended
    }

    /// A clock jump further ahead than this, measured from when the app was installed, is not a Listen day.
    static let clockHorizon: TimeInterval = 5 * 365 * 24 * 60 * 60

    static let dateAheadMessage = "The date on this Mac is too far ahead. Set the date, then try Listen again."

    static func phase(startedOn: Date?, now: Date, highWater: Date? = nil) -> Phase {
        guard let startedOn else { return .notStarted }
        // A start day in the future means the clock was ahead on the first Listen.
        // Moving it back must not open those 14 days again.
        if now < startedOn { return .ended }
        let mark = self.elapsedMark(now: now, startedOn: startedOn, highWater: highWater)
        let elapsed = self.elapsedUTCDays(from: startedOn, to: mark)
        let remaining = ConnectingCaptionsProduct.listenTrialDays - elapsed
        if remaining <= 0 { return .ended }
        return .inTrial(daysRemaining: remaining)
    }

    /// nil when `now` is too far after the app was installed to treat as the first Listen.
    static func acceptedNow(_ now: Date, appBirth: Date?) -> Date? {
        guard let appBirth, appBirth.timeIntervalSince1970 > 1_577_836_800 else { return now }
        if now.timeIntervalSince(appBirth) > self.clockHorizon { return nil }
        return now
    }

    /// The latest honest day. A backward step keeps the old mark. A multi-year jump is ignored.
    static func advanceHighWater(_ highWater: Date?, now: Date, appBirth: Date?) -> Date? {
        guard let accepted = self.acceptedNow(now, appBirth: appBirth) else { return highWater }
        guard let highWater else { return accepted }
        if accepted <= highWater { return highWater }
        if accepted.timeIntervalSince(highWater) > self.clockHorizon { return highWater }
        return accepted
    }

    private static func elapsedMark(now: Date, startedOn: Date, highWater: Date?) -> Date {
        guard let highWater, highWater >= startedOn else { return now }
        return max(now, highWater)
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
