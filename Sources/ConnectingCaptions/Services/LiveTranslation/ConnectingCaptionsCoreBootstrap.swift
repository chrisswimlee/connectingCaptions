import Foundation

/// Wires the shared core logger to the macOS diagnostic log.
enum ConnectingCaptionsCoreBootstrap {
    static func install() {
        CoreLog.debugHandler = { message, source in
            DebugLogger.shared.debug(message, source: source)
        }
        CoreLog.infoHandler = { message, source in
            DebugLogger.shared.info(message, source: source)
        }
        CoreLog.warningHandler = { message, source in
            DebugLogger.shared.warning(message, source: source)
        }
        CoreLog.errorHandler = { message, source in
            DebugLogger.shared.error(message, source: source)
        }
        PlatformHost.current = MacPlatformHost()
        ListenLanguageID.resolve = { SpokenLanguageResolver.listenLanguageID(for: $0) }
    }
}
