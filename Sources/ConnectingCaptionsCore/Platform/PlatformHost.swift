import Foundation

/// Windows, pasteboard, haptics, and microphone permission.
/// Each app implements this. Caption math stays in ConnectingCaptionsCore.
public protocol ConnectingCaptionsPlatformHost: AnyObject {
    func performAlignmentHaptic()
    func copyToPasteboard(_ text: String)
    var isOpenedFromDownload: Bool { get }
    func revealDownloadedApp()
    func microphoneAuthorizationRawValue() -> Int
    func requestMicrophoneAccess() async -> Bool?
}

public enum PlatformHost {
    public static var current: ConnectingCaptionsPlatformHost = NullPlatformHost()
}

public final class NullPlatformHost: ConnectingCaptionsPlatformHost {
    public init() {}

    public func performAlignmentHaptic() {}
    public func copyToPasteboard(_ text: String) { _ = text }
    public var isOpenedFromDownload: Bool { false }
    public func revealDownloadedApp() {}
    public func microphoneAuthorizationRawValue() -> Int { 0 }
    public func requestMicrophoneAccess() async -> Bool? { nil }
}
