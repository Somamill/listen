# Native preview validation

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
