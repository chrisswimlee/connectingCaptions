import Foundation

/// User-facing identity for the direct-download Mac app. The GitHub repo stays `connectingCaptions`.
nonisolated public enum ConnectingCaptionsProduct {
    public static let displayName = "Connecting Captions Pro"
    /// Release `.app` folder name in `/Applications` and inside the download zip.
    public static let bundleFileName = "Connecting Captions Pro"
    /// GitHub Release zip: `Connecting-Captions-{version}.zip`
    public static let releaseDownloadPrefix = "Connecting-Captions"
    /// Earlier Connecting Captions zip names this updater still accepts.
    /// fluidSubtitles 1.6.12 looks up `fluidsubtitles-{version}.zip` itself. That file is
    /// signed as `com.fluidsubtitles.app` and is not a zip this build installs.
    public static let legacyReleaseDownloadPrefixes = ["connectingcaptions"]
    public static let shortName = "Connecting Captions Pro"
    #if os(iOS)
    /// Direct-download iPhone and iPad app. The App Store app is `com.connectingcaptions.ios`.
    public static let bundleIdentifier = "com.connectingcaptions.ios.pro"
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
    /// Mac and direct-download iPhone and iPad builds live in this repo. The App Store app is `connectingCaptions-iOS`.
    public static let githubRepo: String? = "connectingCaptions"
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
    public static let commercialLicenseEmail = "support@local-host.ai"
    public static let commercialLicenseURL = URL(string: "https://local-host.ai/connectingCaptions/license/")!
    /// Pricing page with the Paddle checkout for a personal key. The checkout link lives on the page, so it can change without an app release.
    public static let personalPurchaseURL = URL(string: "https://local-host.ai/connectingCaptions/pricing/")!
    public static let productPageURL = URL(string: "https://local-host.ai/connectingCaptions/")!
    public static let licenseKeychainService = "com.connectingcaptions.commercial-license"
    public static let licenseKeychainAccount = "connectingCaptionsCommercialLicense"
    public static let trialKeychainAccount = "connectingCaptionsListenTrial"
    public static let workNoticeTitle = "Trial"
    public static let personalLicensePriceLine = "$49 once"
    public static let personalLaunchPriceLine = "$29 once"
    public static let listenTrialDays = 14
    /// Direct Mac and iPhone downloads stay free until the App Store app is available.
    /// The 14-day clock stays in the code and starts only when this is true.
    public static let directDownloadAsksForKey = false
    /// UTC day the paid Listen gate ships. Files created before this day are an earlier copy.
    public static let earlierCopyCutoffDay = "2026-11-02"
    public static let personalMacs = 2
    public static let workNotice =
        "A 14-day trial, then $49 once for up to two Macs you own. Updates for version 1. A named license is $240 per Mac per year, or $120 for schools, five Macs minimum, and is required when an organization owns the Mac. A written SLA is $3,000 per organization per year. An installer package is $2,500 once."
    public static let commercialSeatPriceLine = "$240 / Mac / year ($120 for schools)"
    public static let commercialSLAPriceLine = "$3,000 / organization / year"
    public static let commercialMDMPriceLine = "$2,500 once"
    public static let commercialSeatMinimum = 5

    /// Optional note from an early download. There is no donation checkout yet.
    public static var donateMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = self.commercialLicenseEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Connecting Captions Pro donation"),
            URLQueryItem(
                name: "body",
                value: "I downloaded Connecting Captions Pro early. I'd like to donate.\n"
            ),
        ]
        return components.url ?? URL(string: "mailto:\(self.commercialLicenseEmail)")!
    }

    public static var commercialLicenseMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = self.commercialLicenseEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Connecting Captions Pro commercial license"),
            URLQueryItem(name: "body", value: """
                Organization:

                Mac count (5 minimum):

                Named license $240/Mac/year ($120/Mac/year for schools). School? (yes/no)

                Add written SLA $3,000/organization/year? (yes/no)

                MDM / Jamf pkg $2,500 once? (yes/no)

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
