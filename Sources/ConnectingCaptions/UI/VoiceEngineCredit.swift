import SwiftUI

/// Shown with the publisher line. The git credits do not travel inside the notarized app.
struct VoiceEngineCredit: View {
    var body: some View {
        Text(Self.line)
            .fixedSize(horizontal: false, vertical: true)
    }

    static var line: AttributedString {
        let name = ConnectingCaptionsProduct.voiceEngineUpstreamName
        var text = AttributedString("Speech recognition from \(name) by altic-dev.")
        if let range = text.range(of: name) {
            text[range].link = ConnectingCaptionsProduct.voiceEngineUpstreamURL
            text[range].underlineStyle = .single
        }
        return text
    }
}
