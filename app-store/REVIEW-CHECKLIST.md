# Release validation

## Reproduce without credentials

Use Xcode with iOS and Mac Catalyst SDKs. Open `ios/Listen.xcodeproj`; ZIPFoundation is locked to 0.9.20. No developer team is embedded in the project.

```sh
xcodebuild -project ios/Listen.xcodeproj -scheme Listen -configuration Release -destination 'generic/platform=iOS' -archivePath build/listen-ios.xcarchive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive
python3 ios/scripts/check_bundle.py build/listen-ios.xcarchive/Products/Applications/Listen.app
xcodebuild -project ios/Listen.xcodeproj -scheme Listen -configuration Release -destination 'generic/platform=macOS,variant=Mac Catalyst' -archivePath build/listen-mac.xcarchive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive
python3 ios/scripts/check_bundle.py 'build/listen-mac.xcarchive/Products/Applications/listen Player.app'
```

These commands produce unsigned archives for validation, not App Store uploads. Native CI also builds the simulator and Mac Catalyst editions.

## Review paths

Core use requires no account. Import a personal DRM-free MP3 or M4B through Files, play it, adjust speed, add a bookmark, pause/resume and use a sleep timer. Check nested folders, queues, metadata editing and MP3-to-M4B conversion. Imported originals remain available.

On signed devices, test iCloud with the same Apple account on iPhone, iPad and Mac: import a book, wait for upload, download it on another device, play there and check position on returning. Test offline playback, incoming share imports, widget continuation and background audio. Do not present this as verified from an unsigned simulator.

Goodreads is optional. Test connection in the app's own web session, Want to Read/Currently Reading/Read separation, disconnect and CSV import. Website availability is controlled by Goodreads. Own-server connections are optional; no reviewer login is needed for the core app.

For browser transfer, start the temporary session on a trusted local network, import through the secret link, and confirm closing the screen stops the listener.

## Submission

Check the public privacy policy against current behavior, then complete Apple's privacy and age-rating questionnaires truthfully, including embedded website access. Capture actual current-version iPhone, iPad and Mac screenshots without private account data or invented content. Set free/paid availability intentionally. Validate signed archives and all extensions, upload, associate the processed builds, and submit both platforms. Never accept missing iCloud permissions as a successful release.
