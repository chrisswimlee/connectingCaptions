//
//  AppNavigationState.swift
//  fluid
//
//  Navigation state shared by the main app and settings sidebars.
//

import Foundation

enum SidebarItem: Hashable {
    case liveTranslation
    case speakAndType
    case welcome
    case voiceEngine
    case translationEngine
    case languagePacks
    case aiEnhancements
    case cleanupStyles
    case customDictionary
    case stats
    case history
    case changelog
    case feedback

    var accessibilityIdentifier: String {
        switch self {
        case .liveTranslation: return "sidebar.theater"
        case .speakAndType: return "sidebar.speakAndType"
        case .welcome: return "sidebar.welcome"
        case .voiceEngine: return "sidebar.voiceEngine"
        case .translationEngine: return "sidebar.translationEngine"
        case .languagePacks: return "sidebar.languagePacks"
        case .aiEnhancements: return "sidebar.aiProviders"
        case .cleanupStyles: return "sidebar.cleanupStyles"
        case .customDictionary: return "sidebar.customDictionary"
        case .stats: return "sidebar.stats"
        case .history: return "sidebar.history"
        case .changelog: return "sidebar.changelog"
        case .feedback: return "sidebar.feedback"
        }
    }

    /// Hidden FluidVoice leftovers resolve to an advertised destination.
    var advertisedDestination: SidebarItem {
        switch self {
        case .translationEngine:
            return .languagePacks
        case .customDictionary, .aiEnhancements, .cleanupStyles:
            return .welcome
        case .stats:
            return .history
        default:
            return self
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case translation
    case speakAndType
    case general
    case dictation
    case aiProviders
    case notifications
    case audio
    case dataAndDiagnostics
    case experimental

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .translation: return "Theater"
        case .speakAndType: return "Speak and type"
        case .general: return "General"
        case .dictation: return "Dictation"
        case .aiProviders: return "AI Providers"
        case .notifications: return "Notifications"
        case .audio: return "Audio"
        case .dataAndDiagnostics: return "Data & Diagnostics"
        case .experimental: return "Experimental"
        }
    }

    /// Settings this product advertises. Dictation leftovers stay in the
    /// enum for backups but are not a sidebar destination or search hit.
    static var productSections: [SettingsSection] {
        Self.allCases.filter { $0 != .dictation && $0 != .aiProviders && $0 != .experimental }
    }

    /// Hidden settings resolve to Theater.
    var advertisedDestination: SettingsSection {
        Self.productSections.contains(self) ? self : .translation
    }

    var systemImage: String {
        switch self {
        case .translation: return "captions.bubble"
        case .speakAndType: return "text.cursor"
        case .general: return "gearshape"
        case .dictation: return "keyboard"
        case .aiProviders: return "cpu"
        case .notifications: return "bell"
        case .audio: return "mic"
        case .dataAndDiagnostics: return "wrench.and.screwdriver"
        case .experimental: return "flask"
        }
    }
}

struct SettingsNavigationState: Equatable {
    var selectedSection: SettingsSection?
    private(set) var returnDestination: SidebarItem = .welcome

    var isPresented: Bool {
        self.selectedSection != nil
    }

    func isLeaving(_ section: SettingsSection, for destination: SettingsSection?) -> Bool {
        self.selectedSection == section && destination != section
    }

    mutating func present(_ section: SettingsSection, returningTo currentDestination: SidebarItem?) {
        if !self.isPresented {
            self.returnDestination = currentDestination ?? .welcome
        }
        self.selectedSection = section
    }

    mutating func dismiss() -> SidebarItem {
        self.selectedSection = nil
        return self.returnDestination
    }

    mutating func leaveForApp() {
        self.selectedSection = nil
    }
}
