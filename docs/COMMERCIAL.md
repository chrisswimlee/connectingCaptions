# Commercial license

The published Mac download, release 1.6.16, is free until the App Store app is available. It does not ask for a key. The trial described below is not in that release.

Listen runs for 14 days from the first Listen, then needs a key. The check stays on this Mac. It does not phone home.

A personal key for this download is **$49 once**, or **$29 once** during the Show HN launch week. It covers one person, up to two of their own Macs, and updates for all of version 1. A named organization key is for Macs an organization owns. The App Store app is a separate binary. This repository stays the direct download.

**Buy a personal key:** [local-host.ai/connectingCaptions/pricing](https://local-host.ai/connectingCaptions/pricing/). Checkout is Paddle. The key arrives by email within a minute, signed by `checkout-worker/`. To issue one by hand, run the script with `--personal`.

**Buy a named license:** [local-host.ai/connectingCaptions/license](https://local-host.ai/connectingCaptions/license/) or email [support@local-host.ai](mailto:support@local-host.ai?subject=connectingCaptions%20commercial%20license) with the organization and Mac count.

## Price

| | Price | Notes |
| --- | --- | --- |
| App Store app | **Free** | iPhone and iPad. One full Listen session, with translation, then the unlock. |
| iPhone and iPad unlock | **$9.99 once** | Unlimited Listen, captions, and the keyboard that types the last line. Apple Speech and Apple Translation. |
| Direct download | **$49 once** | This Mac app. Overlay, any input including loopback, Whisper, and typing into other apps. 14-day trial. One person, up to two of their own Macs. Updates for version 1. **$29 once** during the Show HN launch week. |
| Work license | **$240 / Mac / year** | **$120 / Mac / year** for schools. Five Macs minimum. The organization's name on the Mac. Direct download only. Required when an organization owns the Mac. |
| Written SLA | **$3,000 / organization / year** | Flat add-on to the work license. |
| Installer package | **$2,500 once** | Add-on to the work license. |

Apple Speech is the default for one speaker. Either way downloads Whisper Small once if the room talks both languages of the pair. The download is the trial build. Custom overlay or glossary work is [Engage](https://chrisswimlee.com/engage/), not this license.

This is not consulting. Consulting is [Engage](https://chrisswimlee.com/engage/).

## What IT usually asks

**How does this monetize?** Direct download $49 once after a 14-day trial, $29 during the Show HN launch week. Work license $240 per Mac per year, $120 for schools, five Macs minimum, required when an organization owns the Mac. Written SLA $3,000 per organization per year. Installer package $2,500 once. The App Store app is iPhone and iPad: one full Listen session, then $9.99 once. Not transcripts, voiceprints, or model training.

**Does voice leave this Mac?** No, unless someone opts in to a cloud speech model. There is no analytics host. Live Theater does not send telemetry. See the README Privacy section.

**Who patches a break?** Security reports go to [SECURITY.md](../SECURITY.md) and get a reply within 7 days. A paid license can add a written SLA.

GPLv3 still covers this download. Anyone who receives a copy can get the source for that version from the matching git tag, and can share it. A personal key unlocks the notarized app on up to two Macs that person owns, with updates for version 1. A work license is the vendor paper and the signed key that shows **Licensed to** the organization. It is required when the organization owns the Mac.

## What a paid license includes

- A personal key unlocks Listen on up to two Macs one person owns. The card says **Personal license**. It does not say **Licensed to**
- A named organization license and an air-gapped activation key
- The same security mailbox, with an optional written SLA (`--sla` on the key)
- A **Licensed to {org}** line in Settings, Getting Started, Feedback, and Theater Home so procurement can see the Mac is covered
- Optional seat enforcement: a signed list of hardware UUIDs. A Mac outside that list does not show **Licensed to**, and Listen stays off on that Mac
- A Jamf or Fleet `.pkg` that installs the app, the key, the seat list, and a caption-policy file
- Fleet settings backup and restore for caption policy only
- An on-device audit log. It records license, seat, and Listen start or stop. It does not record captions

The key does not lock Talk notes, the dictionary, or export. Listen needs the trial or a key that covers this Mac. A Listen already running finishes when the trial ends. The next Listen is the one that stops.

## How a key works

The token is `base64url(json).base64url(ed25519)`.

JSON fields: `product` (`connectingCaptions`), `org`, `seats`, `issued` (`YYYY-MM-DD`), `expires` (`YYYY-MM-DD`). Optional: `sla` (`true`), `enforceSeats` (`true`), `personal` (`true`), `major` (a version number). Older keys omit those and keep working. A personal key is `personal: true`, `seats` 1 or 2, `major: 1`, and no SLA or seat list. `org` on that key is the buyer email. The app does not show it as **Licensed to**. Version 2 of the app rejects a version 1 key.

The app verifies the signature with the public key in `CommercialLicense.swift`. It does not phone home. Expired or tampered keys fail closed.

Paste the token in **Settings → General**. Remove it from the same row. **Seat ID** on that row is this Mac's hardware UUID.

## Seat list

When the key has `enforceSeats`, **Licensed to** appears only if this Mac's hardware UUID is on a signed seat list for the same organization, and the list is not longer than `seats`. Listen uses the same rule.

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
./scripts/issue-commercial-license.sh --personal --buyer "ada@example.com"
./scripts/issue-commercial-license.sh --org "Example LLP" --seats 25 --expires 2027-09-21
./scripts/issue-commercial-license.sh --org "Example LLP" --seats 25 --expires 2027-09-21 --sla --enforce-seats
```

`--personal` covers two Macs when `--seats` is omitted, and includes updates for version 1. `--issued` defaults to today (UTC). The script prints the token. Send that token to the buyer. Do not commit it. The source for that version is the git tag that matches the app version. The $29 launch price is a Paddle discount code for Show HN week. The key is the same key.

Generate a new pair only when you intend to ship a new public key:

```bash
./scripts/issue-commercial-license.sh --generate-key
```
