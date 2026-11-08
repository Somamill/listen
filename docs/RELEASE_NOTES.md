## listen. 0.2.0 · public beta

A glass-inspired audiobook discovery app for macOS, with the ◒ icon.

- Light, dark, and system appearance; language and category filters.
- Persistent Goodreads sign-in inside listen., independent of Safari, and automatic My Books refresh while the app is open.
- Larger metadata covers, with a restricted private image cache and a typographic fallback.
- Goodreads books linked to audiobook-edition searches; downloads start only when you choose an edition.
- qBittorrent, Transmission, and Deluge Web adapters; magnet handoff for other clients.
- Live torrent-health badges and all-torrent status.
- Local-first downloads and explicit Send to library transfers, including client-aware moves for seeding.
- Fixed embedded-browser form origin errors and startup packaging; background library scanning.

### Downloads

Choose arm64 for Apple Silicon or x86_64 for Intel. The Python runtime is included; a torrent client is separate. SHA-256 checksums are attached.

### Beta limits

Ad-hoc signed, not Developer ID signed or notarized. macOS may block downloaded binaries. macOS 13+ only. Client adapters have automated coverage, with live qBittorrent checks; other client versions require validation. Goodreads depends on website markup and a valid session; session expiry requires signing in again. Refresh is read-only, limited to 2,000 books per cycle, and runs while listen. is open. This is not official OAuth or two-way Goodreads sync. Some sign-in providers may restrict embedded browser sign-in. Public feed availability varies. Catalog availability depends on the external site. Torrent health does not verify file safety or anonymity.
