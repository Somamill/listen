# App Store release candidate

Version 1.0.0 (3), iPhone/iPad and Mac Catalyst. Updated 14 November 2026.

The Mac App Store edition is a sandboxed, self-contained native player. The separate desktop torrent/catalog app has a different bundle identifier and remains installed as `listen.app`. The Store edition builds as `listen Player.app`.

## Verified

- Both current-source unsigned Release archives build successfully.
- Both packages pass checks for sample checksum, main executable, widget/share executables, matching version/build numbers, identifiers and privacy manifest.
- Main, widget and share identifiers are registered; the App Group is assigned to all three and the iCloud container to the main app.
- A website-generated iOS main profile includes the required iCloud permissions. API-generated main profiles still omit those permissions and must not be used.
- App Store Connect has iOS and macOS version 1.0.0 listing drafts: https://appstoreconnect.apple.com/apps/6834434329/distribution. Descriptions, keywords, support URL, category and review contact are saved.
- Source contains no signing credentials, profiles or private account details.

## Still required before submission

- Signing remains stopped at the user's request to avoid keychain password prompts. No signing/password workaround is attempted.
- Generate a valid Mac main distribution profile through Apple's website when its developer session is available.
- Sign and export both editions, verify all extensions and sandbox/iCloud permissions, then validate and upload the binaries.
- Verify real-device iCloud transfer and playback continuation, background audio, share extension and widget using signed builds. Unsigned builds cannot establish these guarantees.
- Complete Store screenshots for all required device families, privacy answers, age rating, pricing/availability and any account-specific compliance requirements.
- Associate validated builds and submit both platform versions for review. Publication follows Apple's approval.

There are currently no uploaded builds and no review submissions. GitHub source preparation is not an App Store release. Temporary Safari JavaScript automation is disabled.

## Identifiers

- Main: `io.github.somamill.listen.mobile`
- Widget: `io.github.somamill.listen.mobile.widgets`
- Share: `io.github.somamill.listen.mobile.share`
- Group: `group.io.github.somamill.listen.mobile`
- iCloud: `iCloud.io.github.somamill.listen.mobile`
