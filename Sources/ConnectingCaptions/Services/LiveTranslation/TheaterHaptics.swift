import Foundation

/// Trackpad alignment click. Buttons stay still; the click is the press.
enum TheaterHaptics {
    static func alignment() {
        PlatformHost.current.performAlignmentHaptic()
    }
}
