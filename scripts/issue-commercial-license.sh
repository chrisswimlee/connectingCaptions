#!/bin/bash
# Issue a connectingCaptions commercial license token.
# The Ed25519 private key never belongs in git.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_KEY="${HOME}/.config/connectingcaptions/commercial-license.ed25519"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/issue-commercial-license.sh --org "Example LLP" --seats 25 --expires 2027-09-21
  ./scripts/issue-commercial-license.sh --org "Example LLP" --seats 25 --expires 2027-09-21 --sla --enforce-seats
  ./scripts/issue-commercial-license.sh --personal --buyer "ada@example.com"
  ./scripts/issue-commercial-license.sh --generate-key

Private key, standard Base64 of 32 raw bytes:
  CONNECTINGCAPTIONS_LICENSE_PRIVATE_KEY
  or ~/.config/connectingcaptions/commercial-license.ed25519 (mode 600)

Optional: --issued YYYY-MM-DD (UTC, default today)
          --sla              written SLA
          --enforce-seats    Licensed to requires a signed seat list
          --personal         up to two Macs, $49 once ($29 launch week). Updates for version 1.
          --buyer            email stored on a personal key. It is not shown as Licensed to.
EOF
}

ORG=""
SEATS=""
EXPIRES=""
ISSUED=""
GENERATE=0
SLA=0
ENFORCE=0
PERSONAL=0
BUYER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --org) ORG="${2:-}"; shift 2 ;;
        --seats) SEATS="${2:-}"; shift 2 ;;
        --expires) EXPIRES="${2:-}"; shift 2 ;;
        --issued) ISSUED="${2:-}"; shift 2 ;;
        --sla) SLA=1; shift ;;
        --enforce-seats) ENFORCE=1; shift ;;
        --personal) PERSONAL=1; shift ;;
        --buyer) BUYER="${2:-}"; shift 2 ;;
        --generate-key) GENERATE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ "$PERSONAL" == 1 ]]; then
    if [[ "$SLA" == 1 || "$ENFORCE" == 1 ]]; then
        echo "A personal key covers one person. Leave off --sla and --enforce-seats." >&2
        exit 1
    fi
    if [[ -n "$SEATS" && "$SEATS" != 1 && "$SEATS" != 2 ]]; then
        echo "A personal key covers one or two Macs." >&2
        exit 1
    fi
    if [[ -z "$SEATS" ]]; then
        SEATS=2
    fi
    if [[ -z "$ORG" ]]; then
        ORG="${BUYER:-Personal}"
    fi
fi

PRIVATE_KEY="${CONNECTINGCAPTIONS_LICENSE_PRIVATE_KEY:-}"
if [[ -z "${PRIVATE_KEY}" && -f "${DEFAULT_KEY}" ]]; then
    PRIVATE_KEY="$(tr -d '[:space:]' < "${DEFAULT_KEY}")"
fi

swift - "$ROOT" "$GENERATE" "$ORG" "$SEATS" "$EXPIRES" "$ISSUED" "$PRIVATE_KEY" "$DEFAULT_KEY" "$SLA" "$ENFORCE" "$PERSONAL" <<'SWIFT'
import CryptoKit
import Foundation

let args = CommandLine.arguments
let generate = args[2] == "1"
let org = args[3]
let seatsText = args[4]
let expires = args[5]
let issuedArg = args[6]
let privateKeyBase64 = args[7]
let defaultKeyPath = args[8]
let includeSLA = args[9] == "1"
let enforceSeats = args[10] == "1"
let personal = args[11] == "1"

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

if generate {
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: defaultKeyPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try key.rawRepresentation.base64EncodedString().write(toFile: defaultKeyPath, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: defaultKeyPath)
    FileHandle.standardError.write(Data("Wrote private key to \(defaultKeyPath)\n".utf8))
    FileHandle.standardError.write(Data("Public key (bake into CommercialLicense.swift):\n".utf8))
    print(key.publicKey.rawRepresentation.base64EncodedString())
    exit(0)
}

guard !org.isEmpty, let seats = Int(seatsText), seats >= 1 else {
    FileHandle.standardError.write(Data("Need --org, --seats (>= 1), and --expires YYYY-MM-DD.\n".utf8))
    exit(1)
}
if personal && (seats < 1 || seats > 2 || includeSLA || enforceSeats) {
    FileHandle.standardError.write(Data("A personal key covers one or two Macs, with no SLA and no seat list.\n".utf8))
    exit(1)
}

let days = dayFormatter()
let expiresDate: String
if expires.isEmpty {
    guard personal else {
        FileHandle.standardError.write(Data("Need --expires YYYY-MM-DD.\n".utf8))
        exit(1)
    }
    expiresDate = "2099-12-31"
} else {
    guard days.date(from: expires) != nil else {
        FileHandle.standardError.write(Data("expires must be YYYY-MM-DD.\n".utf8))
        exit(1)
    }
    expiresDate = expires
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

struct Wire: Encodable {
    var product: String
    var org: String
    var seats: Int
    var issued: String
    var expires: String
    var sla: Bool?
    var enforceSeats: Bool?
    var personal: Bool?
    var major: Int?

    enum CodingKeys: String, CodingKey {
        case product, org, seats, issued, expires, sla, enforceSeats, personal, major
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(product, forKey: .product)
        try container.encode(org, forKey: .org)
        try container.encode(seats, forKey: .seats)
        try container.encode(issued, forKey: .issued)
        try container.encode(expires, forKey: .expires)
        try container.encodeIfPresent(sla, forKey: .sla)
        try container.encodeIfPresent(enforceSeats, forKey: .enforceSeats)
        try container.encodeIfPresent(personal, forKey: .personal)
        try container.encodeIfPresent(major, forKey: .major)
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(
    Wire(
        product: "connectingCaptions",
        org: org,
        seats: seats,
        issued: issued,
        expires: expiresDate,
        sla: includeSLA ? true : nil,
        enforceSeats: enforceSeats ? true : nil,
        personal: personal ? true : nil,
        major: personal ? 1 : nil
    )
)
let signature = try privateKey.signature(for: data)
print("\(base64URL(data)).\(base64URL(signature))")
SWIFT
