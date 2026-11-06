import Foundation
import zlib

/// Names from a Keynote file. A `.key` package or zip holds snappy-compressed
/// slide archives, or an older `index.apxl`. Media stays unread.
enum KeynoteSlideText {
    static let maxOutputBytes = 4_000_000
    static let maxIWABytes = 8_000_000

    static func plainText(inIWA data: Data) -> String {
        guard !data.isEmpty, data.count <= Self.maxIWABytes else { return "" }
        let payloads = self.iwaPayloads(data)
        guard !payloads.isEmpty else { return "" }
        var pieces: [String] = []
        for payload in payloads {
            pieces.append(contentsOf: self.utf8Runs(payload))
        }
        return pieces.joined(separator: "\n")
    }

    static func plainText(inAPXL data: Data) -> String {
        let xmlData = self.inflateGzip(data, maxOutput: Self.maxOutputBytes) ?? data
        guard let xml = String(data: xmlData, encoding: .utf8) else { return "" }
        return self.xmlText(xml)
    }

    static func xmlText(_ xml: String) -> String {
        var output = ""
        var inTag = false
        for scalar in xml.unicodeScalars {
            if scalar == "<" {
                inTag = true
                output.append("\n")
                continue
            }
            if scalar == ">" {
                inTag = false
                continue
            }
            if !inTag {
                output.unicodeScalars.append(scalar)
            }
        }
        return output
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    /// Snappy block format. Returns nil when the block is truncated or oversized.
    static func decompressSnappy(_ data: Data, maxOutput: Int) -> Data? {
        guard maxOutput > 0, !data.isEmpty else { return nil }
        guard let (length, start) = self.varint(data, 0), length <= maxOutput else { return nil }
        var index = start
        var output = Data()
        output.reserveCapacity(length)
        while index < data.count, output.count < length {
            let tag = data[index]
            index += 1
            switch tag & 0x03 {
            case 0:
                guard let literal = self.literal(data, tag: tag, index: &index) else { return nil }
                output.append(literal)
            case 1:
                let copyLength = Int((tag >> 2) & 0x07) + 4
                guard index < data.count else { return nil }
                let offset = (Int(tag & 0xE0) << 3) | Int(data[index])
                index += 1
                guard self.appendCopy(&output, length: copyLength, offset: offset, limit: length) else { return nil }
            case 2:
                let copyLength = Int(tag >> 2) + 1
                guard index + 1 < data.count else { return nil }
                let offset = Int(data[index]) | (Int(data[index + 1]) << 8)
                index += 2
                guard self.appendCopy(&output, length: copyLength, offset: offset, limit: length) else { return nil }
            default:
                let copyLength = Int(tag >> 2) + 1
                guard index + 3 < data.count else { return nil }
                var offset = 0
                for shift in 0..<4 {
                    offset |= Int(data[index + shift]) << (8 * shift)
                }
                index += 4
                guard self.appendCopy(&output, length: copyLength, offset: offset, limit: length) else { return nil }
            }
            if output.count > length { return nil }
        }
        guard output.count == length else { return nil }
        return output
    }

    private static func iwaPayloads(_ data: Data) -> [Data] {
        var index = 0
        var payloads: [Data] = []
        var total = 0
        while index + 4 <= data.count, total < Self.maxOutputBytes, payloads.count < 64 {
            guard data[index] == 0 else { break }
            let length = Int(data[index + 1]) | (Int(data[index + 2]) << 8) | (Int(data[index + 3]) << 16)
            index += 4
            guard length > 0, index + length <= data.count, length <= Self.maxIWABytes else { break }
            let chunk = data.subdata(in: index..<(index + length))
            index += length
            guard let plain = self.decompressSnappy(chunk, maxOutput: Self.maxOutputBytes - total) else { continue }
            payloads.append(plain)
            total += plain.count
        }
        return payloads
    }

    private static func literal(_ data: Data, tag: UInt8, index: inout Int) -> Data? {
        let coded = Int(tag >> 2)
        let literalLength: Int
        if coded < 60 {
            literalLength = coded + 1
        } else {
            let extra = coded - 59
            guard extra >= 1, extra <= 4, index + extra <= data.count else { return nil }
            var value = 0
            for shift in 0..<extra {
                value |= Int(data[index + shift]) << (8 * shift)
            }
            index += extra
            literalLength = value + 1
        }
        guard literalLength > 0, index + literalLength <= data.count else { return nil }
        let bytes = data.subdata(in: index..<(index + literalLength))
        index += literalLength
        return bytes
    }

    private static func appendCopy(_ output: inout Data, length: Int, offset: Int, limit: Int) -> Bool {
        guard offset > 0, offset <= output.count, length > 0, output.count + length <= limit else { return false }
        for _ in 0..<length {
            output.append(output[output.count - offset])
        }
        return true
    }

    private static func varint(_ data: Data, _ start: Int) -> (Int, Int)? {
        var result = 0
        var shift = 0
        var index = start
        while index < data.count, shift <= 28 {
            let byte = Int(data[index])
            index += 1
            result |= (byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (result, index) }
            shift += 7
        }
        return nil
    }

    private static func utf8Runs(_ data: Data) -> [String] {
        var pieces: [String] = []
        var current = Data()
        func flush() {
            defer { current.removeAll(keepingCapacity: true) }
            guard current.count >= 2, current.count <= 400,
                  let text = String(data: current, encoding: .utf8)
            else { return }
            let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            guard letters >= 2 else { return }
            pieces.append(text)
        }
        for byte in data {
            if byte < 32 {
                flush()
            } else {
                current.append(byte)
                if current.count > 400 { flush() }
            }
        }
        flush()
        return pieces
    }

    private static func inflateGzip(_ source: Data, maxOutput: Int) -> Data? {
        guard source.count >= 10, source[0] == 0x1F, source[1] == 0x8B else { return nil }
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            16 + MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var output = Data()
        let status: Int32 = source.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return Z_DATA_ERROR }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(source.count)
            let chunk = 16 * 1024
            var inflateStatus = Z_OK
            while inflateStatus == Z_OK, output.count < maxOutput {
                var buffer = [UInt8](repeating: 0, count: chunk)
                let produced: Int = buffer.withUnsafeMutableBytes { dest in
                    stream.next_out = dest.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunk)
                    inflateStatus = inflate(&stream, Z_NO_FLUSH)
                    return chunk - Int(stream.avail_out)
                }
                if produced > 0 {
                    output.append(contentsOf: buffer.prefix(produced))
                }
            }
            return inflateStatus
        }
        guard status == Z_STREAM_END, output.count <= maxOutput else { return nil }
        return output
    }
}
