import SwiftUI

struct DiagnosticLogClearButton: View {
    @State private var clearing = false
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AppButton("Clear Diagnostic Logs", role: .destructive) {
                self.clearing = true
                self.status = ""
                Task {
                    do {
                        try await DebugLogger.shared.clearDiagnostics()
                        self.status = AppLanguage.text("Diagnostic logs cleared.")
                    } catch {
                        self.status = AppLanguage.text("Could not clear every diagnostic log. Check file permissions and try again.")
                    }
                    self.clearing = false
                }
            }
            .buttonStyle(.bordered)
            .disabled(self.clearing)
            .accessibilityIdentifier("settings.clearDiagnosticLogs")
            AppText("Removes current and rotated diagnostic logs, including speech text recorded by older versions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !self.status.isEmpty {
                Text(self.status).font(.caption)
            }
        }
    }
}
