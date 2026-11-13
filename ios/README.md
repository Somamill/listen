# listen. for iPhone & iPad

A native SwiftUI audiobook player in listen.’s sage/forest identity. **This is a developer preview, not an App Store or TestFlight release and not complete BookPlayer feature parity.** No torrent code, catalog, or downloading from torrent sources is included. The macOS app remains separate.

## Build and run

1. Open `Listen.xcodeproj` in Xcode. The generated project is committed; `project.yml` is the reproducible source (`xcodegen generate --spec ios/project.yml` from the repository root).
2. Select the Listen scheme and an iPhone or iPad simulator. Deployment target: iOS/iPadOS 17+. Built locally with Xcode 27.2. Older SDKs use audio-session activation off the main thread; SDK 27 uses the new asynchronous activation API.
3. For a physical device, choose your Apple development team and a unique bundle identifier under Signing & Capabilities. Enable Background Audio and iCloud Documents + key-value storage. Update the container identifiers in `Listen.entitlements`, `Info.plist`, and `CloudLibrary.swift` together. The placeholder is `iCloud.io.github.somamill.listen.mobile`.
4. iCloud requires an Apple account and a provisioned iCloud container. An unsigned simulator build shows a truthful unavailable/off state; it cannot prove cross-device sync.

```sh
xcodebuild -project ios/Listen.xcodeproj -scheme Listen \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/listen-ios-build CODE_SIGNING_ALLOWED=NO test
```

## Import and listen

Use **Library → ＋ → Import audio files** or **Import a folder**. Files/iCloud Drive providers, AirDrop/open-in, and file sharing into the app’s Documents folder can supply audio; use the Files picker to import shared documents. MP3, M4B, M4A, FLAC, WAV, AAC and AIFF are accepted when AVFoundation can decode them. DRM-protected files are rejected. Imports copy audio into the app library and never modify your original source files. Multiple selected audio files combine into a book in natural filename order; switch combining off to import them separately. A folder containing book subfolders groups those subfolders separately.

Your existing Mac audiobook folder is **not hard-coded or automatically accessible on iOS**. Select it through Files → iCloud Drive. Imported books use the app’s own iCloud container for later sync.

- Playback position, finished state, folders/queues, chapter navigation, speed (0.5–3×), 15/30-second skips, smart rewind, sleep timer, bookmarks, AirPlay and lock-screen/headset commands.
- Edit title, author, narrator and folder in a book’s **Edit** screen. Books in the same folder continue in library order.
- Metadata uses embedded tags first. Optional automatic lookup sends title/author text to Apple Books Search, applies only confident matches, and downloads cover art. Audio is never sent to the lookup service. You can keep embedded metadata and edit manually.
- Optional automatic MP3 conversion, or **Create M4B audiobook** on a book. This **decodes MP3 and encodes AAC**, joins tracks, writes title/author/artwork and Nero-style chapter markers, and verifies duration/playability before changing the library record. Originals stay in the local library. Use the book’s Share button to export converted audio to Files, including another iCloud Drive folder. MP3→AAC is lossy; automatic conversion defaults off. Keep the app in the foreground for long conversions. At most 255 chapter markers are supported. Some other players may not read Nero-style chapters; listen. also retains its chapter index.

## iCloud behavior

Books and manifests live in the app’s iCloud Documents container; the local library caches files for offline playback. Remote audio downloads before playback. Progress also uses iCloud key-value storage and resolves conflicts by update timestamp with a deterministic device-ID tie-break. Active local playback is not jumped to a remote position. File upload completion and network availability are controlled by iCloud; “sync” is not an upload guarantee.

This preview needs **real-device testing with the same signed Apple account on two devices**: upload/download completion, interrupted transfers, device lock, long books, storage pressure and concurrent playback. Source code and conflict tests do not certify these behaviors end to end. Goodreads cookies, credentials, and shelves are not synced through iCloud.

## Goodreads

Connect inside the app’s dedicated website view, or paste your profile/My Books link. Its WKWebView session is independent of Safari. Shelf extraction is read-only and refreshes while the app is open, up to 2,000 books per cycle. Want to Read, Currently Reading, Read and Did Not Finish stay separate. Listening progress does **not** silently alter Goodreads reading status.

Goodreads can expire sessions, block embedded third-party sign-in, or change its page structure. Use **Other ways → Import Goodreads CSV** as a supported snapshot fallback. No sign-in or live shelf verification has been performed using a personal account in this preview. No API credentials, scraper service, or Goodreads password is embedded in the project.

## Compared with BookPlayer

[BookPlayer](https://github.com/TortugaPower/BookPlayer) is a feature reference, not copied source. listen.’s iOS implementation is independent and follows this repository’s MIT license.

| Capability | Preview state |
| --- | --- |
| Local import, multi-track books, playback, progress, chapters, speed, skips | Implemented; simulator tests |
| Bookmarks, sleep timer, smart rewind, finished state, simple folders/queues | Implemented; some UI flows tested, hardware/background checks remain |
| Embedded and automatic metadata, covers, MP3→AAC/M4B with chapters | Implemented; generated-audio conversion and metadata matching tests |
| iCloud audio library and progress | Implemented; signed two-device verification required |
| Goodreads shelves and independent website session | Implemented; CSV tested, authenticated website sync unverified |
| Dark/light appearance, native iPad split view, Dynamic Type, VoiceOver labels | Native implementation; simulator visual review, assistive-device audit remains |
| ZIP import, Audiobookshelf/Jellyfin server integrations | Not implemented in this preview |
| Library reorder | Implemented through native Edit controls; use the All shelf without a search |
| Nested playlists and audio volume boost | Not implemented in this preview |
| Apple Watch, CarPlay, widgets, alternative icons | Not implemented in this preview |
| App Store signing, provisioning, privacy submission and TestFlight | Not completed |

## Before distribution

Use a real development/distribution team, provision the container, verify account flows, audit the privacy manifest and Apple Books/Goodreads network disclosures, exercise large libraries and real headphones/background audio, and prepare App Store screenshots and accessibility/localization checks. No App Store eligibility or review outcome is promised. All bundled sample audio is a generated test tone, not an audiobook.
