# Install and use listen. on a Mac

## Start without connection setup

1. Download the matching **Apple Silicon (arm64)** or **Intel (x86_64)** DMG from [Releases](https://github.com/Somamill/listen/releases). Requires macOS 13 or later.
2. Open the DMG and drag **listen.app** to **Applications**. Python, Homebrew, Docker, and developer tools are not needed.
3. Have a torrent app installed that accepts magnet links, such as [qBittorrent](https://www.qbittorrent.org/download). The torrent app is separate from listen.
4. Open listen., search for a book, inspect its edition, and press **＋**. New installs use the Mac’s default torrent app. Confirm the download and destination there.

The public beta is ad-hoc signed and **not notarized**. macOS may require manual approval to open it. Follow [Apple’s guidance](https://support.apple.com/102445); do not disable system security protections. If your organization blocks unnotarized software, use an approved build or ask its administrator.

## Connect a client for download status and library transfers

Open **Settings → Your torrent client** and choose qBittorrent, Transmission, or Deluge Web. Enable the client’s Web/RPC interface and enter its actual address and credentials. Save and test the connection. listen. does not turn off client authentication or change its privacy settings.

Common address examples:

- qBittorrent: `http://127.0.0.1:8080`.
- Transmission: `http://127.0.0.1:9091/transmission/rpc`.
- Deluge Web: `http://127.0.0.1:8112`; enable Web and connect its daemon.

Use your own configured port, not necessarily these examples. For remote clients, use HTTPS where available and choose folders that exist on the client’s computer, including an absolute Windows path if that client runs on Windows. Remote clients must already be running.

For local qBittorrent, automatic startup is on by default: listen. opens the app in the background, waits for its Web UI, and then sends the download. Install and enable its Web UI first. You can turn automatic startup off in Settings. If a watchdog closes the client, resolve its warning rather than disabling it.

Languages and category filters are optional and neutral on new installs. Leaving them empty includes everything. Filters depend on catalog metadata and are reapplied before adding an edition.

## Connect Goodreads

Choose **Connect Goodreads** and sign in on the real Goodreads website in the **Goodreads · listen.** window. Your account is your own; no profile or password is bundled. The app retains its own WebKit session and refreshes your My Books shelves every five minutes while open. Safari and other browsers can be closed. The connection resumes on launch; if Goodreads expires it, sign in again here.

Shelves are separated into Want to Read, Currently Reading, Read, and Did Not Finish. Up to 2,000 books refresh per cycle. Choose **Find audiobook** to search the title and author, then review the edition. No downloads start automatically from a shelf. Local listening progress does not change Goodreads ratings or shelves.

CSV import, manual Safari-page import, and browser bookmarklet/pasted book links are available under **Other ways to bring your books**. These imports are snapshots. Safari Automation is optional and is not needed for the main Goodreads connection.

## Local downloads and the library button

With a direct client connection, choose a downloads folder and a separate library folder in Settings. Local downloads finish locally first; incomplete files may be staged locally by qBittorrent or Deluge. Nothing is sent to iCloud automatically.

Use **Send to library** on a completed download, or **Local library** for finished files that the connected local client no longer manages. Managed torrents move through the client so it can keep track for seeding. Existing destination names are checked before local moves; cloud synchronization is handled by macOS. Remote file operations and collisions are managed by the remote client.

In default-app handoff mode, the torrent app controls all locations, progress, and file moves. Connect its Web/RPC interface to manage those in listen. Keep cloud files downloaded if you continue seeding them.

## Updates and appearance

In **Settings → About**, choose **Check for updates**. Open the linked official GitHub release, download the matching architecture, quit listen., and replace the app in Applications. Settings, reading history, Goodreads website session, and client downloads live outside the bundle and are retained. Updating listen. does not update your torrent client.

Choose System, Light glass, or Dark glass. `⌘,` opens Settings. `⌃⌘L` hides the listen. windows behind a Mac-authentication lock; it does not lock other apps or encrypt files.
