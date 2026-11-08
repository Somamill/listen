# Privacy & security model

listen. is a local desktop front end. It is not a VPN, anonymity network, firewall, or kill switch. No setup is guaranteed 100% leak-proof.

## Network paths

- Catalog searches and public Goodreads-link resolution use the app service’s normal network connection with HTTPS certificate validation.
- Goodreads sign-in and browsing use your chosen browser’s connection and session.
- Torrent peers, trackers, DNS behavior, proxies, VPN binding, and inbound exposure are controlled by your torrent client and operating system.
- No peer-health request is sent to external trackers by a search preview. Health comes from the configured client’s API after a torrent is added.
- listen. does not change system DNS, proxies, VPNs, firewall rules, browser preferences, or torrent network privacy settings.

Do not assume your torrent client’s proxy also protects catalog searches, browser traffic, or DNS. A SOCKS proxy does not by itself encrypt the connection to that proxy. Review the client’s configuration separately.

## Local service

The packaged service binds to a dynamically selected `127.0.0.1` port. A random local token, a strict Host check, same-origin checks for mutations, and an HttpOnly SameSite cookie protect its UI. The token is stored in files readable by the current user. Files and settings are not isolated from other programs running with access to that same user account.

The UI uses a restrictive content policy and no third-party scripts, fonts, or tracking pixels. Metadata cover images are fetched over normal HTTPS from a restricted Goodreads/Amazon/Open Library image-host allowlist (including restricted Internet Archive cover-image redirects), then cached privately on the Mac for seven days. Those hosts see the app service’s IP and image request; the browser does not load covers directly from them. Typographic artwork remains the fallback. Basic process/error logs remain on the Mac. Book URLs and magnets are not intentionally logged.

## Credentials & reading data

Client passwords use the operating system credential store (macOS Keychain in the native release). They are not returned by the Settings API or saved in JSON settings. Goodreads passwords and cookies remain in the browser; listen. does not copy the browser’s cookie database.

The main Goodreads connection uses a dedicated WebKit window inside listen. Its persistent website data store retains that Goodreads session separately from Safari. Sign-in is sent directly to Goodreads or the sign-in provider you choose; login-page source is never imported. After sign-in, only Goodreads home/profile navigation and your own My Books shelf source are read, parsed locally, and discarded. Book metadata is stored on the Mac. Shelves refresh every five minutes while listen. is open and resume on launch; session expiry requires signing in again. Disconnect stops refresh and retains saved books. The website session remains in the app’s WebKit data store until you sign out on Goodreads. No password or session cookies are copied to the local Python service. Optional public-feed connection stores a profile ID and polls Goodreads directly; some profiles do not provide public feeds. Manual Safari import remains optional and only reads a page requested by the user.

The browser bookmarklet sends a Goodreads book URL, title, and author to the local `listen://` app handler. Review data before sharing screenshots or filing issues. Do not attach your service token, credential-store exports, browser cookies, settings, logs containing personal data, or private library exports to public issues.

## Trust & releases

The public beta is ad-hoc signed, not Developer ID notarized. Checksums identify release files but are not a malware assessment. Source and automated build workflows are public. Use only releases from this project’s repository and review code before building.

Please report security-sensitive issues privately; see [SECURITY.md](../SECURITY.md).
