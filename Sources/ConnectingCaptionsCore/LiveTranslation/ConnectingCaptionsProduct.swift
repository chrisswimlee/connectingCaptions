import Foundation

/// User-facing identity. The GitHub repo and bundle file name stay `connectingCaptions`.
nonisolated public enum ConnectingCaptionsProduct {
    public static let displayName = "Connecting Captions"
    /// Release `.app` folder name in `/Applications` and inside the download zip.
    public static let bundleFileName = "Connecting Captions"
    /// GitHub Release zip: `Connecting-Captions-{version}.zip`
    public static let releaseDownloadPrefix = "Connecting-Captions"
    /// Earlier Connecting Captions zip names this updater still accepts.
    /// fluidSubtitles 1.6.12 looks up `fluidsubtitles-{version}.zip` itself. That file is
    /// signed as `com.fluidsubtitles.app` and is not a zip this build installs.
    public static let legacyReleaseDownloadPrefixes = ["connectingcaptions"]
    public static let shortName = "Captions"
    #if os(iOS)
    public static let bundleIdentifier = "com.connectingcaptions.ios"
    #else
    public static let bundleIdentifier = "com.connectingcaptions.app"
    #endif
    public static let tagline = "Each sentence appears when it is ready."
    public static let manifesto = "Language is no longer a barrier."

    public static let supportFolderName = "connectingCaptions"
    /// Earlier names of this app. FluidVoice is a different product and is not migrated.
    public static let priorSupportFolderNames = ["fluidSubtitles"]
    public static let keychainService = "com.connectingcaptions.provider-api-keys"
    public static let keychainAccount = "connectingCaptionsApiKeys"
    public static let priorKeychainIdentities: [(service: String, account: String)] = [
        ("com.fluidsubtitles.provider-api-keys", "fluidSubtitlesApiKeys"),
    ]

    public static var keychainLookupIdentities: [(service: String, account: String)] {
        [(self.keychainService, self.keychainAccount)] + self.priorKeychainIdentities
    }

    public static let githubOwner: String? = "chrisswimlee"
    #if os(iOS)
    public static let githubRepo: String? = "connectingCaptions-iOS"
    #else
    public static let githubRepo: String? = "connectingCaptions"
    #endif
    public static let helpURL = URL(string: "https://github.com/chrisswimlee/connectingCaptions/issues/new/choose")
    public static let feedbackURL = URL(string: "https://github.com/chrisswimlee/connectingCaptions/issues/new?labels=bug")
    public static let discussionsURL = URL(string: "https://github.com/chrisswimlee/connectingCaptions/discussions")
    public static let examplesURL = URL(string: "https://github.com/chrisswimlee/connectingCaptions#theater-captions")

    public static let authorName = "Chris Swim Lee"
    public static let authorSiteHost = "chrisswimlee.com"
    public static let authorURL = URL(string: "https://chrisswimlee.com")!
    public static let publisherName = "Local Host AI"
    public static let publisherSiteHost = "local-host.ai"
    public static let publisherURL = URL(string: "https://local-host.ai")!
    public static let voiceEngineUpstreamName = "FluidVoice"
    public static let voiceEngineUpstreamURL = URL(string: "https://github.com/altic-dev/FluidVoice")!
    public static let commercialLicenseEmail = "suyoung.lee99@gmail.com"
    public static let commercialLicenseURL = URL(string: "https://chrisswimlee.com/connectingCaptions/license/")!
    public static let licenseKeychainService = "com.connectingcaptions.commercial-license"
    public static let licenseKeychainAccount = "connectingCaptionsCommercialLicense"
    public static let workNoticeTitle = "For work"
    public static let workNotice =
        "Free for everyone under GPLv3, work use included. Named license is $60 per Mac per year, five Macs minimum. Written SLA is +$90 per Mac per year. A Jamf or Fleet pkg is $1,500 once."
    public static let commercialSeatPriceLine = "$60 / Mac / year"
    public static let commercialSLAPriceLine = "+$90 / Mac / year"
    public static let commercialMDMPriceLine = "$1,500 once"
    public static let commercialSeatMinimum = 5

    public static var commercialLicenseMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = self.commercialLicenseEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Connecting Captions commercial license"),
            URLQueryItem(name: "body", value: """
                Organization:

                Mac count (5 minimum):

                Named license $60/Mac/year. Add written SLA +$90/Mac/year? (yes/no)

                MDM / Jamf pkg $1,500 once? (yes/no)

                Anything else IT or legal needs:
                """),
        ]
        return components.url ?? URL(string: "mailto:\(self.commercialLicenseEmail)")!
    }

    public static let creditShort =
        "A product of Local Host AI. GPLv3."

    public static var updateRepository: (owner: String, repo: String)? {
        guard let owner = self.githubOwner, let repo = self.githubRepo,
              !owner.isEmpty, !repo.isEmpty
        else {
            return nil
        }
        return (owner, repo)
    }

    public static var releasesURL: URL? {
        guard let repository = self.updateRepository else { return nil }
        return URL(string: "https://github.com/\(repository.owner)/\(repository.repo)/releases")
    }

    public static var issuesURL: URL? {
        guard let repository = self.updateRepository else { return nil }
        return URL(string: "https://github.com/\(repository.owner)/\(repository.repo)/issues/new/choose")
    }

    /// Developer ID team IDs allowed to install updates, in addition to the running app’s team.
    /// Suyoung Lee / Chris Swim Lee, Developer ID Application (C6BH3WS28B).
    public static let allowedUpdateTeamIDs: Set<String> = ["C6BH3WS28B"]
}
