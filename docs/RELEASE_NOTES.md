## Meet listen.

A glass-inspired audiobook discovery app for macOS with a native shell and a bundled local runtime.

- Light, dark, and system appearance.
- Language, category inclusion/exclusion, and tag filters.
- One-button Goodreads connection through a dedicated Safari window, automatic shelf refresh, metadata covers, and cross-browser book-link fallbacks.
- Direct qBittorrent, Transmission, and Deluge Web adapters; magnet handoff for other clients.
- Live client-derived torrent-health badges and all-torrent download status.
- Local-first downloads, explicit Send to library transfers, and client-aware moves that preserve the torrent’s location for seeding.
- Client passwords in the system credential store and an authenticated loopback UI.

### Downloads

Choose `arm64` for Apple Silicon or `x86_64` for Intel. The app includes its Python runtime. A torrent client is separate. SHA-256 checksums are attached.

### Public beta limits

These builds are ad-hoc signed, not Developer ID signed or notarized; macOS may block downloaded binaries. Native release packages are macOS-only. Client adapters have automated coverage, with live end-to-end checks performed using qBittorrent. Goodreads imports depend on browser permissions and website markup; this is not official OAuth or two-way Goodreads sync. Torrent health is neither file-safety verification nor an anonymity or completion guarantee.

See the repository README and privacy guide for setup, support boundaries, and known limitations.

- One-button Goodreads connection through a dedicated Safari window, automatic shelf pagination/refresh, and truthful reconnect state.
- Metadata cover images with a restricted private image cache.
- Fixed embedded-browser form origin errors with page security tokens. Local library scanning runs in the background.
