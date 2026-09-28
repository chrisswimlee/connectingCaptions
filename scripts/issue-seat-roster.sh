#!/bin/bash
# Sign a connectingCaptions seat list. Seat ids are hardware UUIDs.
# The Ed25519 private key never belongs in git.
set -euo pipefail

DEFAULT_KEY="${HOME}/.config/connectingcaptions/commercial-license.ed25519"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/issue-seat-roster.sh --org "Example LLP" --expires 2027-09-21 --seat UUID --seat UUID
  ./scripts/issue-seat-roster.sh --org "Example LLP" --expires 2027-09-21 --seats-file ./seats.txt

Private key, standard Base64 of 32 raw bytes:
  CONNECTINGCAPTIONS_LICENSE_PRIVATE_KEY
  or ~/.config/connectingcaptions/commercial-license.ed25519 (mode 600)

--seats-file is one hardware UUID per line. Blank lines and # comments are ignored.
Optional: --issued YYYY-MM-DD (UTC, default today)
EOF
}

ORG=""
EXPIRES=""
ISSUED=""
SEATS_FILE=""
SEAT_LIST=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --org) ORG="${2:-}"; shift 2 ;;
        --expires) EXPIRES="${2:-}"; shift 2 ;;
        --issued) ISSUED="${2:-}"; shift 2 ;;
        --seats-file) SEATS_FILE="${2:-}"; shift 2 ;;
        --seat)
            SEAT_LIST="${SEAT_LIST}"$'\n'"${2:-}"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ -n "${SEATS_FILE}" ]]; then
    if [[ ! -f "${SEATS_FILE}" ]]; then
        echo "Seat file not found: ${SEATS_FILE}" >&2
        exit 1
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "${trimmed}" || "${trimmed}" == \#* ]] && continue
        SEAT_LIST="${SEAT_LIST}"$'\n'"${trimmed}"
    done < "${SEATS_FILE}"
fi

PRIVATE_KEY="${CONNECTINGCAPTIONS_LICENSE_PRIVATE_KEY:-}"
if [[ -z "${PRIVATE_KEY}" && -f "${DEFAULT_KEY}" ]]; then
    PRIVATE_KEY="$(tr -d '[:space:]' < "${DEFAULT_KEY}")"
fi

swift - "$ORG" "$EXPIRES" "$ISSUED" "$PRIVATE_KEY" "$DEFAULT_KEY" "$SEAT_LIST" <<'SWIFT'
import CryptoKit
import Foundation

let args = CommandLine.arguments
let org = args[1]
let expires = args[2]
let issuedArg = args[3]
let privateKeyBase64 = args[4]
let defaultKeyPath = args[5]
let seatBlob = args[6]

func dayFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func isSeatID(_ raw: String) -> Bool {
    let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        .uppercased()
    guard (8 ... 64).contains(id.count) else { return false }
    return id.allSatisfy { $0.isHexDigit || $0 == "-" }
}

let seats = seatBlob
    .split(whereSeparator: \.isNewline)
    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }

guard !org.isEmpty, !expires.isEmpty, !seats.isEmpty, seats.allSatisfy(isSeatID) else {
    FileHandle.standardError.write(Data("Need --org, --expires YYYY-MM-DD, and at least one hardware UUID.\n".utf8))
    exit(1)
}

let days = dayFormatter()
guard days.date(from: expires) != nil else {
    FileHandle.standardError.write(Data("expires must be YYYY-MM-DD.\n".utf8))
    exit(1)
}

let issued: String
if issuedArg.isEmpty {
    issued = days.string(from: Date())
} else {
    guard days.date(from: issuedArg) != nil else {
        FileHandle.standardError.write(Data("issued must be YYYY-MM-DD.\n".utf8))
        exit(1)
    }
    issued = issuedArg
}

guard let keyData = Data(base64Encoded: privateKeyBase64),
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
else {
    FileHandle.standardError.write(Data("Set CONNECTINGCAPTIONS_LICENSE_PRIVATE_KEY or \(defaultKeyPath).\n".utf8))
    exit(1)
}

let canonical = Array(Set(seats.map {
    $0.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        .uppercased()
})).sorted()

struct Wire: Encodable {
    var product: String
    var org: String
    var seatIDs: [String]
    var issued: String
    var expires: String
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(
    Wire(product: "connectingCaptions", org: org, seatIDs: canonical, issued: issued, expires: expires)
)
let signature = try privateKey.signature(for: data)
print("\(base64URL(data)).\(base64URL(signature))")
SWIFT
