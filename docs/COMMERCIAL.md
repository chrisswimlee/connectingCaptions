# Commercial license

connectingCaptions is free for everyone under GPLv3, work use included. Theater Listen stays unlocked. A commercial license is optional.

If IT or legal need a vendor they can sanction — a named license, a security contact, or an SLA — buy a commercial license at the published price.

**Buy:** [chrisswimlee.com/connectingCaptions/license](https://chrisswimlee.com/connectingCaptions/license/) or email [suyoung.lee99@gmail.com](mailto:suyoung.lee99@gmail.com?subject=connectingCaptions%20commercial%20license) with the organization and Mac count.

## Price

| | Price | Notes |
| --- | --- | --- |
| Named license | **$60 / Mac / year** | Five Macs minimum. Air-gapped key. Licensed to the organization. |
| Written SLA | **+$90 / Mac / year** | Security reply in 7 days, plus a weekday window if Listen breaks. |
| MDM / Jamf pkg | **$1,500 once** | App, key, seat list, and caption policy. IT signs the pkg. |

Apple Speech is the default for one speaker. Either way downloads Whisper Small once if the room talks both languages of the pair. The zip stays free. Custom overlay or glossary work is [Engage](https://chrisswimlee.com/engage/), not this license.

This is not consulting. Consulting is [Engage](https://chrisswimlee.com/engage/).

## What IT usually asks

**How does this monetize?** Named license $60 per Mac per year, five Macs minimum. Written SLA +$90 per Mac per year. MDM pkg $1,500 once. Not transcripts, voiceprints, or model training.

**Does voice leave this Mac?** No, unless someone opts in to a cloud speech model. There is no analytics host. Live Theater does not send telemetry. See the README Privacy section.

**Who patches a break?** Security reports go to [SECURITY.md](../SECURITY.md) and get a reply within 7 days. A paid license can add a written SLA.

GPLv3 still lets a firm run the free zip. A commercial license does not forbid work use of that zip. It is the vendor paper and the signed key that shows **Licensed to** the organization in the app.

## What a paid license includes

- A named organization license and an air-gapped activation key
- The same security mailbox, with an optional written SLA (`--sla` on the key)
- A **Licensed to {org}** line in Settings, Getting Started, Feedback, and Theater Home so procurement can see the Mac is covered
- Optional seat enforcement: a signed list of hardware UUIDs. A Mac outside that list does not show **Licensed to**
- A Jamf or Fleet `.pkg` that installs the app, the key, the seat list, and a caption-policy file
- Fleet settings backup and restore for caption policy only
- An on-device audit log. It records license, seat, and Listen start or stop. It does not record captions

The key does not lock Talk notes, the dictionary, export, or Listen. A refused seat still listens. The free zip stays free for everyone.

## How a key works

The token is `base64url(json).base64url(ed25519)`.

JSON fields: `product` (`connectingCaptions`), `org`, `seats`, `issued` (`YYYY-MM-DD`), `expires` (`YYYY-MM-DD`). Optional: `sla` (`true`), `enforceSeats` (`true`). Older keys omit those two and keep working.

The app verifies the signature with the public key in `CommercialLicense.swift`. It does not phone home. Expired or tampered keys fail closed.

Paste the token in **Settings → General**. Remove it from the same row. **Seat ID** on that row is this Mac's hardware UUID.

## Seat list

When the key has `enforceSeats`, **Licensed to** appears only if this Mac's hardware UUID is on a signed seat list for the same organization, and the list is not longer than `seats`.

```bash
./scripts/issue-seat-roster.sh --org "Example LLP" --expires 2027-09-21 \
  --seat "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
```

`--seats-file` is one UUID per line. Jamf and Fleet already inventory that UUID. The token is `seats.roster`.

## Fleet settings

Settings → General can export or restore `settings.fleet.json`. The file is caption policy: languages, spoken line, size, spacing, typeface, appearance, contrast, presentation, and Voice Engine. It rejects any other key, including transcripts, notes, and API keys.

A pkg can drop the same file. The app applies it when the file bytes change. An edit on that Mac stays until IT ships a new file.

```json
{
  "product": "connectingCaptions",
  "iSpeak": "en",
  "showAs": "ko",
  "spokenLine": "afterPause",
  "captionSize": 42,
  "captionSpacing": 14,
  "voiceEngine": "apple-speech",
  "presentation": "popup",
  "appearance": "dark",
  "highContrast": false,
  "typeface": "system"
}
```

## Audit log

Each line is hashed and signed with a key that stays on that Mac. Export writes `audit.json` for IT. Clear deletes the local log. Nothing is uploaded. A line that names a caption, transcript, or audio path is refused.

## MDM package

```bash
./scripts/build-mdm-pkg.sh \
  --app dist/Connecting Captions.app \
  --license ./license.key \
  --roster ./seats.roster \
  --settings ./settings.fleet.json \
  --output dist/connectingCaptions-mdm.pkg
```

The pkg is unsigned. Sign it with a Developer ID Installer certificate before Jamf or Fleet ships it.

It installs the app in `/Applications` and these root-owned files:

- `/Library/Application Support/connectingCaptions/license.key`
- `/Library/Application Support/connectingCaptions/seats.roster`
- `/Library/Application Support/connectingCaptions/settings.fleet.json`

While `license.key` is present, it wins over a key pasted in Settings. The row says **Installed for this Mac.**

## Issue a key (maintainer)

The Ed25519 **private** key never belongs in git.

1. Put the raw 32-byte private key, standard Base64, in `CONNECTINGCAPTIONS_LICENSE_PRIVATE_KEY`, or in `~/.config/connectingcaptions/commercial-license.ed25519` (mode `600`).
2. Confirm the matching public key is the one baked into `Sources/ConnectingCaptions/Services/LiveTranslation/CommercialLicense.swift`. Rotating the key needs a new app release.
3. Issue:

```bash
./scripts/issue-commercial-license.sh --org "Example LLP" --seats 25 --expires 2027-09-21
./scripts/issue-commercial-license.sh --org "Example LLP" --seats 25 --expires 2027-09-21 --sla --enforce-seats
```

`--issued` defaults to today (UTC). The script prints the token. Send that token to the buyer. Do not commit it.

Generate a new pair only when you intend to ship a new public key:

```bash
./scripts/issue-commercial-license.sh --generate-key
```
