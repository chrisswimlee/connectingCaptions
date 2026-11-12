import Foundation
import IOKit.ps

/// Whether this Mac is running on its battery. A desktop, or a laptop on
/// power, is plugged in. The answer is cached for a few seconds so a speech
/// tick does not query IOKit every time.
enum SpeechPowerSource {
    private static let lock = NSLock()
    private static var cached = false
    private static var cachedAt = 0.0

    static var isOnBattery: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        self.lock.lock()
        if now - self.cachedAt < 5 {
            let value = self.cached
            self.lock.unlock()
            return value
        }
        self.lock.unlock()
        let value = self.read()
        self.lock.lock()
        self.cached = value
        self.cachedAt = now
        self.lock.unlock()
        return value
    }

    private static func read() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                as? [String: Any]
            else { continue }
            let state = description[kIOPSPowerSourceStateKey as String] as? String
            if state == kIOPSBatteryPowerValue as String { return true }
        }
        return false
    }
}
