# Get started with listen.

1. Install a matching Mac release and open **listen.**
2. Open **Settings → Your torrent client**. Choose qBittorrent, Transmission, Deluge Web, or magnet handoff.
3. Enable your client’s Web/RPC interface and enter its URL. Use its actual port, credentials, and remote paths. Save, then test the connection.
4. Choose a default downloads folder. Optionally choose a completed-books folder, including a cloud drive. For a remote client, type a path on that remote machine.
5. Choose languages and category filters. Leaving a filter empty includes everything; exclusions use the catalog’s labels.
6. Search for a title or author. Inspect the edition, language, narrator, and metadata before adding it.

## Typical local client URLs

- qBittorrent: `http://127.0.0.1:8080` (use the port configured in your Web UI).
- Transmission: `http://127.0.0.1:9091/transmission/rpc`.
- Deluge Web: `http://127.0.0.1:8112` (enable its Web interface and connect its daemon).

These are examples, not automatic credentials or guaranteed defaults. Remote connections should use HTTPS where supported, especially on untrusted networks.

## From Goodreads to an audiobook

Choose **Bring a Goodreads book**. Sign in to Goodreads in your selected browser. For Safari, open a Goodreads book and use **Use book open in Safari**. For another browser, drag the bookmarklet into its bookmarks bar and click it on a Goodreads book, or paste the URL into listen.

listen. searches by title and author and ranks likely editions first. It cannot prove two editions are identical. No book is downloaded just because it was sent from Goodreads.

For a shelf, open **My Books** in Safari and import the visible page. Open additional pages to add them. You can enable refresh of the active shelf in Settings. A Goodreads CSV export is also supported.

## Destinations and cloud drives

Downloads finish in the local folder selected in Settings. Partial files can be staged locally by qBittorrent or Deluge; Transmission manages its own incomplete directory. Nothing moves to iCloud automatically. Use **Send to library** on a completed download, or open **Local library** to transfer an audiobook that is no longer in the connected client. Choose the library destination in Settings. Existing destination items are not overwritten.

A remote client cannot download directly into a path that exists only on your Mac. Cloud providers can evict local files; keep books downloaded if you continue seeding them. Moving or renaming files outside the client can cause missing-file errors.

## Appearance & shortcuts

Choose **System**, **Light glass**, or **Dark glass** in Settings. The header’s appearance button cycles between them. `⌘,` opens Settings. `⌃⌘L` locks the listen. window; unlocking uses your existing Mac authentication.

Window lock hides this app’s view. It is not full-disk encryption and does not lock your browser, torrent client, or other apps.
