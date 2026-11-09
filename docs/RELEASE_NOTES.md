## listen. 0.3.0 · release-readiness beta

A portable audiobook discovery app for macOS 13+, with separate Apple Silicon and Intel downloads.

- New installs use the default torrent app without requiring a Web UI or embedded credentials. Existing direct-client settings are preserved.
- Optional qBittorrent, Transmission, and Deluge connections provide status, torrent health, and client-aware library moves. Local qBittorrent opens automatically when needed.
- Persistent Goodreads sign-in inside listen., automatic shelf refresh while open, and separate Want to Read, Currently Reading, Read, and Did Not Finish tabs.
- Higher-resolution metadata covers, light/dark/system appearance, and the ◒ app icon.
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
