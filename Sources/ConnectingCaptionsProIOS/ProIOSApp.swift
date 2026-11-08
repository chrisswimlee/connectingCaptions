import SwiftUI

@main
struct ProIOSApp: App {
    @StateObject private var session = ProIOSSession.shared
    @StateObject private var license = ProIOSLicenseStore.shared
    @StateObject private var settings = ProIOSSettings.shared

    var body: some Scene {
        WindowGroup {
            ProIOSHomeView()
                .environmentObject(self.session)
                .environmentObject(self.license)
                .environmentObject(self.settings)
        }
    }
}
