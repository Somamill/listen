# listen. App Store edition — Privacy Policy

Last updated: 13 November 2026

listen. is a personal audiobook player for iPhone, iPad and Mac. This policy covers the native App Store edition. The separate desktop catalogue/torrent application has its own policy.

## Your library

Audio, book metadata, bookmarks, listening history and playback positions are stored in the app's local library. listen. does not operate a developer-hosted account or audio-upload service. Imported original files are retained unless you choose to remove them through the app or your file provider.

## Optional iCloud

When you enable iCloud library sync, library files and metadata are sent to your private Apple iCloud app container. Playback position also uses Apple's iCloud key-value storage. Apple processes this information under its own privacy policy and your iCloud account settings. Sync availability depends on your account, storage and network. Goodreads sessions and media-server credentials are not uploaded to iCloud.

## Optional metadata lookup

Automatic metadata matching sends book title and author text to Apple's Books search service and downloads cover images. Audio is not sent to the metadata service. You can disable automatic matching and edit book information yourself.

## Goodreads

Connecting Goodreads opens Goodreads in an app-specific website session. Sign-in information is submitted to Goodreads or its sign-in provider, and website cookies remain in the app's WebKit storage. Goodreads and any pages opened there are governed by their respective privacy policies. The app stores your selected profile identifier and a local cache of your reading shelves; it does not provide a developer-hosted copy of your account. You may disconnect Goodreads and remove the cached connection in Settings. A CSV import is available instead of website sign-in.

## Your own media server

Audiobookshelf and Jellyfin connections send authentication and download requests directly to the HTTPS server you specify. Server access tokens are stored in the device Keychain, not in configuration JSON or iCloud. Passwords are used for sign-in and are not saved by listen. Removing a server removes its saved token. The server operator can see the requests you send to that server.

## Browser transfer and file downloads

A browser transfer starts only when you enable a temporary session. It uses local HTTP and a secret link on a trusted network; close the transfer screen to stop it. Do not use this feature on an untrusted network. Direct file downloads use HTTPS. Download hosts and your network provider may process connection information under their own policies.

## Widgets and share extension

The widget and share extension use a private App Group shared only by listen.'s signed app components. A widget snapshot contains the current book title, author and progress. Shared audio files are staged there until the main app imports them.

## Analytics and advertising

listen. does not include advertising, a developer analytics service or cross-app tracking SDKs. Apple may provide operating-system and App Store diagnostics according to your device settings. External websites, Apple services and user-selected servers may apply their own logging and privacy practices.

## Your choices and contact

You can disable optional network integrations and iCloud, remove books and connections, and delete the app's data through your device settings. Removing local data does not necessarily remove copies retained by iCloud, external servers, your original Files library or backups. For privacy questions or support, open an issue at https://github.com/Somamill/listen/issues. Do not post passwords, tokens or private files in a public issue.
