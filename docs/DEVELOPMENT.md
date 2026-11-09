# Development

## Architecture

- `native/Listen.swift`: AppKit/WebKit shell, local process lifecycle, browser handoff, folder picker, Mac authentication window lock, a persistent Goodreads WebKit session, and optional manual Safari import.
- `listen_app/server.py`: authenticated loopback UI and application routes.
- `listen_app/catalog.py`: HTTPS catalog parsing and metadata filters.
- `listen_app/clients.py`: qBittorrent, Transmission, Deluge, and magnet adapters.
- `listen_app/health.py`: health labels derived from client-reported metrics.
- `listen_app/settings.py`: validated preferences and system credential-store integration.
- `listen_app/discovery.py`, `safari_bridge.py`, `goodreads_sync.py`: Goodreads metadata imports and local listening progress.
- `scripts/build_macos.py`: PyInstaller service, Swift shell, signing, ZIP/DMG, and checksums.

## Tests

```bash
python -m pip install -c constraints.txt -e '.[build]'
python -m unittest discover -s tests -v
python scripts/check_frontend.py  # requires Node.js for syntax checks
python -m pip_audit
```

Tests use temporary local data and mocked client adapters. They do not download books, contact trackers, or read real browser sessions. Live-client checks are separate; do not treat adapter tests as certification of every server version.

Set `LISTEN_DATA_DIR` to a temporary directory to isolate development, previews, and screenshots. Never publish that directory. The server writes a random port, process ID, and local token to `connection.json`; the native shell validates its own launcher identity before loading the UI. Running the service alone does not expose an unauthenticated browser page.

## Build

Use Python 3.12 for release builds, Xcode Command Line Tools, and a matching-architecture Mac. `python scripts/build_macos.py --dmg` creates architecture-labeled ZIP and DMG files and SHA-256 checksums in `dist/`. The app is built in a temporary directory outside synchronized folders; its location is printed and saved in `build/app-path.txt`. Python is bundled. This is not a universal binary: build Apple Silicon and Intel separately.

`LISTEN_SIGN_IDENTITY` can select a locally available code-signing identity. Default builds use ad-hoc signing. Developer ID signing and Apple notarization require the maintainer’s own Apple credentials and are not performed or claimed by the default workflow.

## Data

Default app data lives under the current user’s `Library/Application Support/listen`. Credentials go to the system credential store. The public project must never contain app data, `.env` files, personal folders, credentials, browser HTML snapshots, or reading history. New users get neutral, inclusive defaults; individual filtering choices belong only in local settings.

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md). Keep credentials and private content out of test fixtures. Use small, synthetic fixtures for parsers and adapter tests. External website markup can change; handle failures explicitly and never disable certificate checks to make a parser work.

Release CI pins its action revisions and uses constraints.txt for the tested dependency versions. Both architectures exercise the frozen service with clean app data, neutral defaults, authenticated pages, and an unauthenticated-request rejection before archives are published. Dependency audit runs separately.
