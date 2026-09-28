import Foundation

/// User-facing identity for fluidSubtitles.
nonisolated enum FluidProduct {
    static let displayName = "fluidSubtitles"
    static let shortName = "Subtitles"
    static let bundleIdentifier = "com.fluidsubtitles.app"
    static let tagline = "Each sentence appears when it is ready."
    static let manifesto = "Language is no longer a barrier."

    static let supportFolderName = "fluidSubtitles"
    /// Earlier name of this app. FluidVoice is a different product and is not migrated.
    static let priorSupportFolderNames = ["connectingCaptions"]
    static let keychainService = "com.fluidsubtitles.provider-api-keys"
    static let keychainAccount = "fluidSubtitlesApiKeys"
    static let priorKeychainIdentities: [(service: String, account: String)] = [
        ("com.connectingcaptions.provider-api-keys", "connectingCaptionsApiKeys"),
    ]

    static var keychainLookupIdentities: [(service: String, account: String)] {
        [(self.keychainService, self.keychainAccount)] + self.priorKeychainIdentities
    }

    static let githubOwner: String? = "chrisswimlee"
    static let githubRepo: String? = "fluidSubtitles"
    static let helpURL = URL(string: "https://github.com/chrisswimlee/fluidSubtitles/issues/new/choose")
    static let feedbackURL = URL(string: "https://github.com/chrisswimlee/fluidSubtitles/issues/new?labels=bug")
    static let discussionsURL = URL(string: "https://github.com/chrisswimlee/fluidSubtitles/discussions")
    static let examplesURL = URL(string: "https://github.com/chrisswimlee/fluidSubtitles#theater-captions")

    static let authorName = "Chris Swim Lee"
    static let authorSiteHost = "chrisswimlee.com"
    static let authorURL = URL(string: "https://chrisswimlee.com")!
    static let commercialLicenseEmail = "suyoung.lee99@gmail.com"
    static let commercialLicenseURL = URL(string: "https://chrisswimlee.com/fluidSubtitles/license/")!
    static let licenseKeychainService = "com.fluidsubtitles.commercial-license"
    static let licenseKeychainAccount = "fluidSubtitlesCommercialLicense"
    static let workNoticeTitle = "For work"
    static let workNotice =
        "Personal, student, and evaluation use is free. If IT or legal need a named license or an SLA, request a commercial license."

    static var commercialLicenseMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = self.commercialLicenseEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "fluidSubtitles commercial license"),
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
        "By Chris Swim Lee. GPLv3."

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
