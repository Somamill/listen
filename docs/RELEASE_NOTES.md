## listen. 0.4.2 · one version per audiobook

- Settings now has a preferred audiobook language. Matching book titles/authors are grouped across languages, with one displayed version per book.
- Selection favors the preferred language first, then completeness, audiobook format, and metadata richness. If the preferred language is unavailable, the best allowed alternative is selected automatically. Different authors and series volumes stay distinct; catalog naming differences can still prevent identification of the same book, particularly translated titles without shared identifiers.
- The preferred language is always eligible; the existing language chips now control allowed fallback languages. Existing preferences migrate without resetting other settings; English is the initial preference and can be changed in Settings.
- Library cleanup, torrent settings, and the matching qBittorrent themes are preserved.

## listen. 0.4.1 · Finder metadata compatibility

Includes the 0.4.0 improvements below. Finder’s `.DS_Store` metadata no longer prevents verified transfer cleanup; only that metadata and empty source directories are removed after media verification. Unexpected source files still prevent cleanup.

## listen. 0.4.0 · library cleanup and preferred editions

- Send to library now verifies local client moves before removing the torrent, preserving the library files and removing empty local download folders. Pending cleanup survives app restarts. Seeding stops after successful transfer; failed verification retains the torrent. Remote clients retain torrents because their files cannot be verified locally.
- Search presents one preferred edition per matching title/author and language, favoring unabridged releases, M4B, then lossless and other known audio formats, with richer metadata breaking ties. Different languages, authors, and series numbers stay separate. Catalog naming differences can still prevent a match; metadata ranking does not certify audio fidelity or torrent health.
- Original light and dark qBittorrent desktop themes complement listen. Editable sources and install instructions are in `extras/qbittorrent`. Theme choice and light/dark switching are manual; native window chrome remains native.
- Existing client privacy settings and Goodreads session are preserved. This remains an ad-hoc signed, unnotarized beta.

## listen. 0.3.1 · release-readiness beta

A portable audiobook discovery app for macOS 13+, with separate Apple Silicon and Intel downloads.

- New installs use the default torrent app without requiring a Web UI or embedded credentials. Existing direct-client settings are preserved.
- Optional qBittorrent, Transmission, and Deluge connections provide status, torrent health, and client-aware library moves. Local qBittorrent opens automatically when needed.
- Persistent Goodreads sign-in inside listen., automatic shelf refresh while open, and separate Want to Read, Currently Reading, Read, and Did Not Finish tabs.
- Higher-resolution metadata covers, light/dark/system appearance, and the ◒ app icon.
- Retry temporary catalog server/network failures once; distinguish outages, certificate failures, rate limits, and missing searches. Never retry a rejected certificate or evade rate limits.
- Search by the main title when a subtitle or series suffix would dilute provider matching; Goodreads author metadata still helps rank editions.
- Catalog search normalization and approved HTTPS redirects; language/category filters are reapplied before adding an edition.
- Local-first downloads for direct local clients and an explicit Send to library action.
- Removed obsolete public-feed and automatic Safari connection experiments, unused endpoints, and stale messages.
- Hardened local navigation, malformed-request handling, session error recovery, window lock, and orphan-service shutdown. Existing local listening-progress keys remain compatible.
- Pinned dependency versions and CI action revisions; dependency audit and clean-data frozen-service checks run before release packaging.

### Install and update

Download arm64 for Apple Silicon or x86_64 for Intel, open the DMG, and drag listen.app to Applications. No Python, Homebrew, or Docker is needed. Install a compatible torrent app separately. To update, quit listen. and replace its app bundle; per-user preferences, client downloads, and Goodreads session are retained.

### Distribution and service limits

This is an **ad-hoc signed, unnotarized public beta**, not a Developer ID distribution. macOS or organizational policy may block opening it. Follow Apple’s documented approval process; do not disable security protections. No automated check can certify every Mac, client version, or torrent.

Goodreads requires your own sign-in. Its session can expire; website changes or sign-in provider restrictions can interrupt sync. Refresh is read-only, runs while listen. is open, and is limited to 2,000 books per cycle. Catalog availability depends on the external site. Magnet handoff delegates destinations/status to the default client. Transmission and Deluge adapters have automated coverage but are not live-certified against all server versions. Torrent health is not file-safety or anonymity verification. listen. does not change system VPN, DNS, proxy, firewall, or torrent privacy settings.

See the repository’s setup, privacy, and release-readiness documents for the full support boundaries.
