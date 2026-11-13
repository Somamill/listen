# BookPlayer comparison and independent implementation

listen. mobile 0.2.0 is a developer preview. It is not a complete BookPlayer replacement or a device-validated App Store release.

## Evidence

On 13 November 2026, [REA](https://github.com/morluto/rea) inspected the **installed BookPlayer 6.0.1 (192)** application bundle in resource-only mode. No BookPlayer account, library, user database, audio, network credentials, purchase state, or private data was read or changed. REA was closed after export. Its raw evidence remains outside this repository because the app's public configuration also contains unrelated service identifiers.

| REA operation | Evidence | What it establishes |
| --- | --- | --- |
| `inspect_plist` | `ev_b14647dcbc427a7cb56f43710566036a5ec1fa20a99f1b8fd9646981aa492ec7` | Version, audio background mode, declared document types, share extension, Siri intent and CarPlay scene declarations. |
| Localized resource inspection | `ev_84b5221087a508cb759a17059a58ec15871877d8f38ecf19cc92cceaf7d733d2` | UI feature descriptions for ZIP import, servers, volume boost, smart rewind, timer choices, bookmark notes/recovery, sorting and transfer queues. |
| `decode_interface_builder` | `ev_33db70db09f4746249c9f2e04edca02a3d52876a869a03d4e758749c273b3651` | Partial static interface structure from nine compiled interface documents; not a complete runtime reconstruction. |

A declaration or translated string proves that an interface contract exists; it does **not** prove runtime behavior, entitlement approval or server availability. Public reference snapshot: `402b650ea6c3bb446b2d42fede15931ee0c109c5`. Public [BookPlayer source](https://github.com/TortugaPower/BookPlayer) was a read-only behavioral reference. No BookPlayer GPL source, icons, artwork, localization tables, hosted-service keys or binary code were incorporated into listen.'s MIT implementation. ZIPFoundation is a separately licensed MIT dependency, pinned to 0.9.20.

## Feature mapping

| Feature | listen. implementation | Practical limit |
| --- | --- | --- |
| Audio and folder imports | Files, open-in, ZIP, share extension, direct HTTPS download, temporary local browser transfer | AVFoundation-readable, unprotected audio; local transfer must be explicitly started on trusted Wi-Fi. |
| ZIP safety | Entry/expanded-size caps, CRC verification, rejection of traversal and symbolic links | 10,000 entries / 20 GB; originals are preserved. |
| Folders and order | Nested folder paths, manual order, title/author/recent/progress/duration/filename sorting, reverse order | Folder metadata is independent of source file locations. |
| Playlists / queue | Persistent explicit play-next queue, reorder/shuffle/remove, optional folder autoplay | Device-local queue, not a server-side playlist editor. |
| Playback | Chapters, speed, configurable skip intervals, AirPlay, headset/lock-screen commands, smart rewind | Device audio routes require hardware verification. |
| Volume boost | Independent 2× PCM gain with clipping; system volume stays unchanged | Louder output can harm hearing; no claim of mastering or noise reduction. |
| Sleep timer | Presets, 1–360-minute custom timer, chapter end, optional final fade | Timer is device-local. |
| Bookmarks | Editable notes and optional automatic recovery before starts/seeks/sleep, capped at 100 automatic marks | Manual bookmarks are retained separately. |
| Listening history | Recent playback events and actual elapsed listening totals | Local history; no analytics upload. |
| Media servers | HTTPS Audiobookshelf and Jellyfin login/token, browse, paginate, download into the local library | No live account supplied; no server progress write-back, Quick Connect or remote transcoding. |
| Server privacy | Keychain tokens, no credentials in URLs/config JSON, same-origin authenticated redirects, TLS validation | Self-signed certificates are not silently trusted. |
| Share / widget / Siri | Share audio/ZIP into inbox, continue-listening widget and App Shortcut | App Group must be provisioned for all three targets; physical-device verification pending. |
| CarPlay | Native library and Now Playing scene adapter with opt-in configuration fragments | Disabled by default; requires Apple's approved audio entitlement and hardware/simulator validation. |
| Metadata / M4B | Embedded metadata, optional Apple Books match and covers; genuine MP3→AAC M4B with chapter markers | Audio is not uploaded; matching can be edited manually. |
| Goodreads | Persisted in-app session, read-only shelf refresh and CSV fallback | No guaranteed perpetual authentication or supported write/progress API. |
| iCloud | App Documents and progress conflict handling from the earlier preview | Requires a signed container and two-device testing. |

Apple Watch, Hardcover, BookPlayer's paid cloud service, alternate paid artwork/icons, Jellyfin Quick Connect, server progress synchronization and full BookPlayer feature parity are **not** included. They are not represented as working controls.

## Optional capabilities

Use a development team and unique identifiers for the app, widget and share targets. Register the same App Group in all three entitlement files and `Shared/CompanionSnapshot.swift`. Provision the app's iCloud container separately. No Max-specific library path or account is embedded.

CarPlay is deliberately opt-in. After Apple approves the audio entitlement, merge `OptionalCapabilities/CarPlay.entitlements.fragment.plist` into the main app entitlements and the corresponding Info fragment into the scene configuration. Preserve existing SwiftUI scene settings. Validate connection, queueing, controls and disconnection using Apple's CarPlay tools and a real supported head unit before distributing it as CarPlay-enabled. Adding a plist key alone does not grant the capability.

See [validation](VALIDATION.md) for executed checks and unresolved verification.
