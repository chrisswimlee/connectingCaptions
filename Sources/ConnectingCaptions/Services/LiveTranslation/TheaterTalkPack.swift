#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import ConnectingCaptionsCore
import Foundation
import PDFKit

/// Local notes or a deck for this talk. Terms stay on the Mac and bias
/// glossary lock. This is not Screen Recording.
nonisolated enum TheaterTalkPack {
    static let maxTerms = TalkPackTerms.maxTerms
    static let maxPromptTerms = TalkPackTerms.maxPromptTerms

    struct Document: Equatable {
        var fileName: String
        var terms: [String]
        var sourceCharacterCount: Int
    }

    enum LoadError: LocalizedError, Equatable {
        case empty
        case unreadable

        var errorDescription: String? {
            switch self {
            case .empty:
                return "That file has no names Theater can keep. A scanned PDF has no text to read; add names by hand below."
            case .unreadable:
                return "Theater could not read that file on this Mac."
            }
        }
    }

    static func load(from url: URL) throws -> Document {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let ext = url.pathExtension.lowercased()
        var isDirectory: ObjCBool = false
        if ext == "key",
           FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue
        {
            let text = try self.keynotePackageText(at: url)
            return try self.document(fromKeynoteText: text, fileName: url.lastPathComponent)
        }
        let data = try Data(contentsOf: url)
        return try self.document(from: data, fileName: url.lastPathComponent)
    }

    static let maxArchiveBytes = 80 * 1_024 * 1_024

    static func document(from data: Data, fileName: String, maxArchiveBytes: Int = Self.maxArchiveBytes) throws -> Document {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "pptx" || ext == "pptm" {
            guard data.count <= maxArchiveBytes else { throw LoadError.unreadable }
            let text = try self.presentationText(from: data)
            let terms = self.extractTerms(from: text)
            guard !terms.isEmpty else { throw LoadError.empty }
            return Document(fileName: fileName, terms: terms, sourceCharacterCount: text.count)
        }

        if ext == "key" {
            guard data.count <= maxArchiveBytes else { throw LoadError.unreadable }
            let text = try self.keynoteZipText(from: data)
            return try self.document(fromKeynoteText: text, fileName: fileName)
        }

        if let pack = try? LectureTermPack.document(from: data) {
            let terms = TalkPackTerms.capped(
                pack.customWords.map(\.text) + pack.replacements.flatMap { $0.from + [$0.to] }
            )
            guard !terms.isEmpty else { throw LoadError.empty }
            return Document(fileName: fileName, terms: terms, sourceCharacterCount: data.count)
        }

        let text = try self.plainText(from: data, fileName: fileName)
        let terms = self.extractTerms(from: text)
        guard !terms.isEmpty else { throw LoadError.empty }
        return Document(fileName: fileName, terms: terms, sourceCharacterCount: text.count)
    }

    /// Names and repeated domain words. The full slide dump is not the glossary.
    static func extractTerms(from text: String) -> [String] {
        TalkPackTerms.extract(from: text)
    }

    static func promptTerms(from terms: [String]) -> [String] {
        TalkPackTerms.promptTerms(from: terms)
    }

    /// Drops leftover slide chrome from an older import before glossary lock.
    static func sanitizedTerms(_ terms: [String]) -> [String] {
        TalkPackTerms.sanitized(terms)
    }

    private static func plainText(from data: Data, fileName: String) throws -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(data: data) else { throw LoadError.unreadable }
            var pages: [String] = []
            pages.reserveCapacity(document.pageCount)
            for index in 0..<document.pageCount {
                pages.append(document.page(at: index)?.string ?? "")
            }
            let text = pages.joined(separator: "\n")
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw LoadError.empty
            }
            return text
        }
        if ext == "rtf" {
            let attributed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return attributed.string
        }
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
        else {
            throw LoadError.unreadable
        }
        return text
    }

    private static func document(fromKeynoteText text: String, fileName: String) throws -> Document {
        let terms = self.extractTerms(from: text)
        guard !terms.isEmpty else { throw LoadError.empty }
        return Document(fileName: fileName, terms: terms, sourceCharacterCount: text.count)
    }

    /// A Keynote package is a directory. Slide archives and `index.apxl` are the text.
    private static func keynotePackageText(at url: URL) throws -> String {
        var parts: [String] = []
        let indexZip = url.appendingPathComponent("Index.zip")
        if FileManager.default.fileExists(atPath: indexZip.path),
           let data = try? Data(contentsOf: indexZip),
           data.count <= Self.maxArchiveBytes,
           let text = try? self.keynoteZipText(from: data)
        {
            parts.append(text)
        }
        let index = url.appendingPathComponent("Index")
        if let files = try? FileManager.default.contentsOfDirectory(
            at: index,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension.lowercased() == "iwa" {
                guard let data = try? Data(contentsOf: file), data.count <= KeynoteSlideText.maxIWABytes else { continue }
                let page = KeynoteSlideText.plainText(inIWA: data)
                if !page.isEmpty { parts.append(page) }
            }
        }
        let apxl = url.appendingPathComponent("index.apxl")
        if let data = try? Data(contentsOf: apxl), data.count <= KeynoteSlideText.maxOutputBytes {
            let page = KeynoteSlideText.plainText(inAPXL: data)
            if !page.isEmpty { parts.append(page) }
        }
        let text = parts.joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LoadError.empty
        }
        return text
    }

    /// Slide text only. Preview images and other zip entries stay unread.
    private static func keynoteZipText(from data: Data) throws -> String {
        guard data.count <= Self.maxArchiveBytes else { throw LoadError.unreadable }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("connectingCaptions-key-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appendingPathComponent("deck.key")
        try data.write(to: archive)
        let names = try self.archiveNames(in: archive)
        var parts: [String] = []
        if names.contains(where: { self.normalizedZipName($0) == "Index.zip" }),
           let nested = try? self.archiveBytes("Index.zip", in: archive)
        {
            let nestedURL = folder.appendingPathComponent("Index.zip")
            try nested.write(to: nestedURL)
            let nestedNames = try self.archiveNames(in: nestedURL)
            for name in nestedNames where self.isNestedKeynoteIWA(name) {
                guard let bytes = try? self.archiveBytes(name, in: nestedURL, allowed: self.isNestedKeynoteIWA) else { continue }
                let page = KeynoteSlideText.plainText(inIWA: bytes)
                if !page.isEmpty { parts.append(page) }
            }
        }
        for name in names where self.isKeynoteIWA(name) {
            guard let bytes = try? self.archiveBytes(name, in: archive) else { continue }
            let page = KeynoteSlideText.plainText(inIWA: bytes)
            if !page.isEmpty { parts.append(page) }
        }
        for name in names where self.normalizedZipName(name) == "index.apxl" {
            guard let bytes = try? self.archiveBytes(name, in: archive) else { continue }
            let page = KeynoteSlideText.plainText(inAPXL: bytes)
            if !page.isEmpty { parts.append(page) }
        }
        let text = parts.joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LoadError.empty
        }
        return text
    }

    /// Slide and notes text only. Other zip entries, including media, stay unread.
    private static func presentationText(from data: Data) throws -> String {
        guard data.count <= Self.maxArchiveBytes else { throw LoadError.unreadable }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("connectingCaptions-pptx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appendingPathComponent("deck.pptx")
        try data.write(to: archive)
        let names = try self.archiveNames(in: archive)
        let parts = self.presentationParts(in: names)
        guard !parts.isEmpty else { throw LoadError.empty }

        var pages: [String] = []
        var counted = 0
        for name in parts.prefix(Self.maxPresentationParts) {
            guard let xml = try? self.archiveEntry(name, in: archive) else { continue }
            let page = self.drawingMLText(xml)
            let trimmed = page.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            pages.append(trimmed)
            counted += trimmed.count + 1
            if counted > Self.maxPresentationCharacters { break }
        }
        let text = pages.joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LoadError.empty
        }
        return text
    }

    private static let maxPresentationParts = 400
    private static let maxPresentationCharacters = 1_500_000

    private static func presentationParts(in names: [String]) -> [String] {
        let slides = names.filter { self.isSlideXML($0) }.sorted { self.partIndex($0) < self.partIndex($1) }
        let notes = names.filter { self.isNotesXML($0) }.sorted { self.partIndex($0) < self.partIndex($1) }
        return slides + notes
    }

    private static func isKeynoteIWA(_ name: String) -> Bool {
        let normalized = self.normalizedZipName(name)
        guard !normalized.contains(".."), !normalized.hasPrefix("/") else { return false }
        return normalized.range(of: #"^Index/[^/]+\.iwa$"#, options: .regularExpression) != nil
    }

    private static func isNestedKeynoteIWA(_ name: String) -> Bool {
        let normalized = self.normalizedZipName(name)
        guard !normalized.contains(".."), !normalized.hasPrefix("/") else { return false }
        if self.isKeynoteIWA(normalized) { return true }
        return normalized.range(of: #"^[^/]+\.iwa$"#, options: .regularExpression) != nil
    }

    private static func isSlideXML(_ name: String) -> Bool {
        name.range(of: #"^ppt/slides/slide[0-9]+\.xml$"#, options: .regularExpression) != nil
    }

    private static func isNotesXML(_ name: String) -> Bool {
        name.range(of: #"^ppt/notesSlides/notesSlide[0-9]+\.xml$"#, options: .regularExpression) != nil
    }

    private static func partIndex(_ name: String) -> Int {
        let digits = name.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    private static func archiveNames(in archive: URL) throws -> [String] {
        let data = try self.unzip(arguments: ["-Z1", archive.path])
        guard let listing = String(data: data, encoding: .utf8) else { throw LoadError.unreadable }
        return listing.split(whereSeparator: \.isNewline).map { line in
            self.normalizedZipName(String(line).trimmingCharacters(in: .whitespaces))
        }
    }

    private static func archiveEntry(_ name: String, in archive: URL) throws -> String {
        guard self.isSlideXML(name) || self.isNotesXML(name) else { throw LoadError.unreadable }
        let data = try self.unzip(arguments: ["-p", archive.path, name])
        guard data.count <= Self.maxPresentationCharacters else { throw LoadError.unreadable }
        guard let xml = String(data: data, encoding: .utf8) else { throw LoadError.unreadable }
        return xml
    }

    private static func archiveBytes(
        _ name: String,
        in archive: URL,
        allowed: ((String) -> Bool)? = nil
    ) throws -> Data {
        let normalized = self.normalizedZipName(name)
        let permits = allowed ?? { self.isKeynoteIWA($0) || $0 == "Index.zip" || $0 == "index.apxl" }
        guard permits(normalized) else { throw LoadError.unreadable }
        let data = try self.unzip(arguments: ["-p", archive.path, normalized])
        guard data.count <= KeynoteSlideText.maxIWABytes else { throw LoadError.unreadable }
        return data
    }

    private static func unzip(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw LoadError.unreadable
        }
        // Drain before waiting so a large slide cannot fill the pipe and stall.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LoadError.unreadable }
        return data
    }

    private static func normalizedZipName(_ name: String) -> String {
        var text = name.replacingOccurrences(of: "\\", with: "/")
        while text.hasPrefix("./") {
            text.removeFirst(2)
        }
        return text
    }

    /// Runs inside one paragraph stay together. A new paragraph is a new line,
    /// so two titles do not glue into one name.
    private static func drawingMLText(_ xml: String) -> String {
        let pattern = #"<a:t(?:\s[^>]*)?>([\s\S]*?)</a:t>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        return xml.components(separatedBy: "</a:p>").compactMap { paragraph -> String? in
            let range = NSRange(paragraph.startIndex..<paragraph.endIndex, in: paragraph)
            let text = regex.matches(in: paragraph, range: range).compactMap { match -> String? in
                guard let span = Range(match.range(at: 1), in: paragraph) else { return nil }
                return self.xmlText(String(paragraph[span]))
            }
            .joined()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n")
    }

    private static func xmlText(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        return text
    }
}
