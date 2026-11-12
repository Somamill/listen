# listen. 0.4.2 release-readiness check

Checked 12 November 2026. This is a tested **public beta**, with the distribution and external-service limits below.

## Validation

| Area | Result and evidence |
| --- | --- |
| Application tests | 40 tests covering local authentication, Host/origin checks, malformed requests, metadata filtering, reading shelves, imports, client adapters, startup, add-result handling, and local transfer safeguards, partial-move cleanup prevention, library file preservation, preferred-edition grouping across languages, preference persistence, preferred-language priority, and format/metadata fallback selection. |
| Frontend | Five rendered pages and 20 inline scripts pass Node.js syntax checks, along with the standalone browser script. Swift shell type-checks. |
| Clean installation | The frozen service is started with a new data directory before packaging. All five pages open, private connection-file permissions and authentication are checked, and neutral preferences are asserted. No existing Mac configuration is required. |
| Architecture packages | Release CI builds Apple Silicon and Intel independently, runs tests and frontend checks, verifies the actual frozen-service startup contract, signs/verifies the bundle ad hoc, and creates ZIP/DMG files and SHA-256 manifests. Publishing depends on both builds passing. |
| Catalog | Live mixed-case public-domain title searches return editions. HTTPS redirects are restricted to approved hosts and may not silently discard a search. |
| Goodreads | A real authenticated session refreshed shelves and survived restarting the app. Reading shelves are separated and unchanged refreshes avoid resetting the current view. No account data is included in this report or the packages. |
| qBittorrent | Live API checks with macOS qBittorrent 5.2.3. Automatic startup and both legacy and structured add results are covered. Existing torrent privacy preferences are retained. |
| Library transfer | A stopped, private synthetic torrent with no trackers was added, moved through the real library-transfer API, and removed. listen. automatically removed the synthetic torrent after the move, the local source was absent, and the destination bytes were preserved. The fixture contained no audiobook content; final test cleanup targeted only its unique hash and file. |
| Dependencies | The checked environment contained 59 audited packages with no known advisories reported. Release dependency versions and CI action revisions are pinned. This is not a guarantee against future advisories or malicious code. |
| Portable preferences | New installs use default-app magnet handoff, unrestricted languages/categories, a per-user downloads path, and no configured library folder. Existing direct-client and library preferences are preserved. No personal profile, proxy endpoint, credentials, reading history, or personal folder is embedded. |
| Cleanup | Removed obsolete public-feed and automatic Safari connection experiments, unreachable connection UI, unused endpoints/imports, and stale sign-in messages. Manual browser/CSV imports and opt-in read-only diagnostics remain useful supported features. |

The light and dark Qt theme resources were validated; the dark theme was applied and visually checked in qBittorrent. All existing torrents and checked privacy/network preferences survived the restart.

## What another user needs

- macOS 13 or later and the matching arm64 or x86_64 download.
- A separate torrent app registered to handle magnet links. Basic handoff requires no Web UI setup. listen. does not include a torrent client.
- Their own Goodreads sign-in if they want Goodreads shelves. Safari is not required for the main connection.
- For in-app client status, health, and file moves: enable that client’s Web/RPC interface and enter its real address and credentials. These cannot be preconfigured for every computer.
- For updates: use Settings → About → Check for updates, then replace the app with the matching official release. Per-user data remains outside the bundle.

## Remaining limits

**Apple distribution:** there is no Developer ID distribution certificate configured for this project. Public builds are ad-hoc signed and unnotarized. macOS or organizational policy may block them. Users must follow [Apple’s documented opening guidance](https://support.apple.com/102445); system security protections should remain enabled. This is not App Store or production-notarized distribution.

**External services:** catalog availability and website markup may change. Goodreads sessions may expire or a sign-in provider may restrict embedded sign-in. Shelf refresh runs while listen. is open, is read-only, and is capped at 2,000 books per cycle. No promise of permanent authentication or future service availability is made.

**Client coverage:** qBittorrent has live local checks. Transmission and Deluge have adapter tests, not live certification against every server version. Remote Windows path handling has automated coverage. Magnet handoff delegates locations, progress, and moves to the selected client. Cloud synchronization and remote-file collisions are controlled by their respective provider/client.

**Privacy and files:** listen. is not a VPN or kill switch and does not certify torrent anonymity, file safety, completion, or speed. No setup is guaranteed leak-proof. Folder moves should be reviewed before use; retain backups of valuable media. Read the [privacy model](PRIVACY.md) and [setup guide](GETTING_STARTED.md).
