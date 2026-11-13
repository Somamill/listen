# Native preview validation — 0.2.0

Checked 13 November 2026 with Xcode 27.2. This is an unsigned developer preview. The [REA evidence and feature matrix](BOOKPLAYER-PARITY.md) distinguishes independently implemented features from BookPlayer declarations and unverified capabilities.

| Check | Result |
| --- | --- |
| Core XCTest | PASS: 16 passed, 1 explicitly skipped, 0 failures. Tests cover genuine AAC conversion/chapter round trips, import grouping/queuing, recovery bookmark limits and legacy decoding, folder paths, PCM gain limits and real audio-tap creation, rewind bounds, elapsed history, mocked server responses and credential origin restrictions. |
| Keychain token storage | UNVERIFIED on a provisioned device. Unsigned simulator returns `errSecMissingEntitlement` (-34018); only that condition skips its dedicated test. Other Keychain errors still fail. The app reports the error and never falls back to plain-text credentials. |
| Browser upload | PASS on simulator loopback: unauthenticated rejection, token-authenticated upload, duplicate rejection and stop state. LAN access/Local Network permission needs a physical device. Active connections are canceled at stop; idle timeout and connection/file limits are enforced. |
| Native iPhone UI | PASS: four flows — library, playback/bookmark/dismissal, Settings and server form. A follow-up playback test also edits and saves bookmark notes after fixing a sheet presentation race. Real screenshots refreshed. |
| Native iPad UI | PASS: all four flows, including server form, 0 failures. Follow-up bookmark note edit/save/dismissal also passes; light appearance screenshots refreshed. |
| Simulator / unsigned iOS Release | Both compile with app, widget and share extension. This does not prove device installation or capability provisioning. |
| Package integrity | PASS: bundled sample checksum matches source, main and extension executables are present, identifiers/version agree. A first build copied a cloud-placeholder resource as zero bytes; resources were hydrated and rebuilt, then all media tests passed. The packaging checker now runs in CI. |
| Browser page design | Hallmark render: 0 FAIL / 1 WARN, tested 320–1920px. The section-count warning is intentionally retained for a single-task transfer utility. Impeccable detector run on the supported HTML surface. Native SwiftUI is validated with builds, XCTest and screenshots, not HTML checks. |
| Personal configuration scan | PASS: no personal Mac paths, Goodreads profile ID, PIA address or qBittorrent WebUI address in mobile source/config/docs. |
| REA provenance | PASS: installed BookPlayer 6.0.1 (192) inspected read-only; public evidence summary committed, raw resource dump excluded. |

The SDK's App Intents training tool logs “Could not archive SSU artifacts” while the build succeeds and intent metadata is emitted. Spoken Siri invocation is therefore **UNVERIFIED**, not treated as a successful runtime check.

The hosted runner exposed an older-SDK CF ownership import difference in `MTAudioProcessingTapCreate`; both managed and Unmanaged API shapes are now supported. CarPlay delegate callbacks explicitly forward to the main actor. The packaged Simulator ZIP also passed extraction, installation and normal app launch on iPad.

Still required before a public device release: a real signing team, App Group/iCloud provisioning, Keychain and share/widget checks on hardware, authenticated Goodreads and media-server accounts, two-device iCloud conflicts/transfers, background/headphone/lock-screen routes, long books/storage pressure, localization and a full assistive-technology audit. CarPlay remains disabled until its approved capability is configured and tested. Apple Watch and complete BookPlayer parity are not included. No live service or entitlement approval is implied by mocks or compiled code.

# Earlier 0.1.0 validation

Checked 13 November 2026 with Xcode 27.2. This is a development preview, not a signed or App Store-ready distribution.

| Check | Result |
| --- | --- |
| Native simulator build | PASS, iPhone and iPad target |
| Unsigned iOS device Release compile | PASS; not a provisioning or installation test |
| Core XCTest suite | PASS, seven tests: import/grouping, original retention, real AAC/M4B conversion, chapter offsets/round trip, local playback/progress, metadata matching, CSV and shelf separation |
| Native iPhone UI | PASS, three flows: library, playback/bookmark/dismissal, Settings |
| Native iPad UI | PASS, three flows; final player artwork dimensions rechecked |
| Independent media verification | PASS, ffprobe recognizes AAC, two chapters, approximately 24.15 seconds from a two-file synthetic MP3 import |
| Metadata endpoint | PASS, public-domain title lookup returned Apple Books audiobook metadata; exact matches and mismatch filtering are covered separately |
| Design | Impeccable native iOS guidance and Hallmark craft principles applied; real simulator screenshots reviewed in phone dark and tablet light appearance, plus accessibility text size. HTML lint is not claimed to validate SwiftUI. |
| Apple signing / TestFlight / App Store | NOT COMPLETED; choose a team and provision the app/container |
| iCloud files/progress between two signed physical devices | UNVERIFIED; capability implementation is not end-to-end account evidence |
| Goodreads authenticated shelf refresh | UNVERIFIED; no personal sign-in performed. CSV parser tests pass, saved in-app website session implementation is included |
| Background lock-screen/headset/AirPlay hardware behavior | UNVERIFIED on physical hardware; audio session, background mode and remote handlers are implemented |
| Long books, concurrent iCloud edits, storage pressure, physical VoiceOver | UNVERIFIED |

Screenshots use a generated test tone, not a real user’s library. The bundled sample seeds only when launched with `--uitesting`. Earlier development checks caught and fixed blocking audio-session activation, explicit player-sheet dismissal, iPad tab querying, and stretched cover bounds; only the final passing runs are treated as evidence.

The first hosted CI build passed compilation but did not start its simulator test session. That obsolete run was cancelled, and CI now chooses the newest installed iOS runtime and explicitly boots it before running tests. Consult the PR’s current checks for hosted results; local simulator evidence above is separate.
