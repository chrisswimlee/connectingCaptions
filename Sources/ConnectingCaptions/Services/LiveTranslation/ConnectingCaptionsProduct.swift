import Foundation

/// User-facing identity. The GitHub repo and bundle file name stay `connectingCaptions`.
nonisolated enum ConnectingCaptionsProduct {
    static let displayName = "Connecting Captions"
    /// Release `.app` folder name in `/Applications` and inside the download zip.
    static let bundleFileName = "Connecting Captions"
    /// GitHub Release zip: `Connecting-Captions-{version}.zip`
    static let releaseDownloadPrefix = "Connecting-Captions"
    /// Earlier release zips the updater still accepts.
    static let legacyReleaseDownloadPrefixes = ["connectingcaptions"]
    static let shortName = "Captions"
    static let bundleIdentifier = "com.connectingcaptions.app"
    static let tagline = "Each sentence appears when it is ready."
    static let manifesto = "Language is no longer a barrier."

    static let supportFolderName = "connectingCaptions"
    /// Earlier names of this app. FluidVoice is a different product and is not migrated.
    static let priorSupportFolderNames = ["fluidSubtitles"]
    static let keychainService = "com.connectingcaptions.provider-api-keys"
    static let keychainAccount = "connectingCaptionsApiKeys"
    static let priorKeychainIdentities: [(service: String, account: String)] = [
        ("com.fluidsubtitles.provider-api-keys", "fluidSubtitlesApiKeys"),
    ]

    static var keychainLookupIdentities: [(service: String, account: String)] {
        [(self.keychainService, self.keychainAccount)] + self.priorKeychainIdentities
    }

    static let githubOwner: String? = "chrisswimlee"
    static let githubRepo: String? = "connectingCaptions"
    static let helpURL = URL(string: "https://github.com/chrisswimlee/connectingCaptions/issues/new/choose")
    static let feedbackURL = URL(string: "https://github.com/chrisswimlee/connectingCaptions/issues/new?labels=bug")
    static let discussionsURL = URL(string: "https://github.com/chrisswimlee/connectingCaptions/discussions")
    static let examplesURL = URL(string: "https://github.com/chrisswimlee/connectingCaptions#theater-captions")

    static let authorName = "Chris Swim Lee"
    static let authorSiteHost = "chrisswimlee.com"
    static let authorURL = URL(string: "https://chrisswimlee.com")!
    static let publisherName = "Local Host AI"
    static let publisherSiteHost = "local-host.ai"
    static let publisherURL = URL(string: "https://local-host.ai")!
    static let voiceEngineUpstreamName = "FluidVoice"
    static let voiceEngineUpstreamURL = URL(string: "https://github.com/altic-dev/FluidVoice")!
    static let commercialLicenseEmail = "suyoung.lee99@gmail.com"
    static let commercialLicenseURL = URL(string: "https://chrisswimlee.com/connectingCaptions/license/")!
    static let licenseKeychainService = "com.connectingcaptions.commercial-license"
    static let licenseKeychainAccount = "connectingCaptionsCommercialLicense"
    static let workNoticeTitle = "For work"
    static let workNotice =
        "Personal, student, and evaluation use is free. If IT or legal need a named license or an SLA, request a commercial license."

    static var commercialLicenseMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = self.commercialLicenseEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Connecting Captions commercial license"),
            URLQueryItem(name: "body", value: """
                Organization:

                Seat count:

                Do you need a written SLA?

                Anything else IT or legal needs:
                """),
        ]
        return components.url ?? URL(string: "mailto:\(self.commercialLicenseEmail)")!
    }

    static let creditShort =
        "A product of Local Host AI. GPLv3."

    static var updateRepository: (owner: String, repo: String)? {
        guard let owner = self.githubOwner, let repo = self.githubRepo,
              !owner.isEmpty, !repo.isEmpty
        else {
            return nil
        }
        return (owner, repo)
    }

    static var releasesURL: URL? {
        guard let repository = self.updateRepository else { return nil }
        return URL(string: "https://github.com/\(repository.owner)/\(repository.repo)/releases")
    }

    static var issuesURL: URL? {
        guard let repository = self.updateRepository else { return nil }
        return URL(string: "https://github.com/\(repository.owner)/\(repository.repo)/issues/new/choose")
    }

    /// Developer ID team IDs allowed to install updates, in addition to the running app’s team.
    /// Suyoung Lee / Chris Swim Lee, Developer ID Application (C6BH3WS28B).
    static let allowedUpdateTeamIDs: Set<String> = ["C6BH3WS28B"]
}
