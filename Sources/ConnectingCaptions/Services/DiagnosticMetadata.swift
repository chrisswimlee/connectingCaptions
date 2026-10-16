import Foundation

/// Error descriptions and provider response bodies may echo speech or prompts.
/// Keep error identity useful without writing user content into diagnostic files.
enum DiagnosticMetadata {
    static func error(_ error: Error) -> String {
        let error = error as NSError
        return "domain=\(error.domain) code=\(error.code)"
    }

    static func promptTrace(title: String, value: String) -> String {
        "[PromptTrace][Dictate] \(title): characters=\(value.count)"
    }
}
