# App Store release candidate

Version 1.0.0 (4), iPhone/iPad and universal Intel/Apple Silicon Mac Catalyst. Updated 14 November 2026.

## Completed

- Both Release archives build and pass packaging checks. All 18 core simulator tests pass, including WebKit content-rule compilation and native DOM extraction with website scripts disabled. Keychain-token tests are excluded to honor the request to avoid password prompts.
- A dedicated listen signing keychain and new identities allow noninteractive signing without changing existing keychain passwords, access controls or existing distribution certificates. Private credentials remain outside the repository.
- Website-generated main profiles grant iCloud permissions on both platforms; all three targets have the shared App Group.
- The iOS app, universal Mac app and both widget/share extensions are signed and strictly verified. The Mac installer signature is verified.
- Apple validation succeeds for both build 4 packages. Uploads have processed as **VALID**, and build 4 is selected for both Store versions.
- Free pricing and availability in all current storefronts are configured. Country-specific compliance remains subject to Apple's submission checks.
- Age-rating capabilities, copyright, review contact and third-party-content declaration are saved.
- Three current native iPhone screenshots, three iPad screenshots and one native Mac screenshot have processed successfully. They show an original sample recording, without private account data or invented book content. The Mac capture uses the same core UI in an isolated preview with a resized window; it does not establish signed-device iCloud behavior.
- Privacy responses are published and the public privacy-policy URL is saved. Optional provider account/website data is disclosed. Goodreads now blocks third-party webpage resources except provider assets and authentication CAPTCHA; page scripts are disabled during shelf refresh.

## Submission status

Both versions were submitted successfully and are **WAITING FOR REVIEW**, with **AFTER_APPROVAL** automatic release enabled.

| Edition | Version/build | Apple status |
| --- | --- | --- |
| iPhone & iPad | 1.0.0 (4) | Waiting for Review |
| Mac Catalyst, Intel & Apple Silicon | 1.0.0 (4) | Waiting for Review |

Neither edition is approved or publicly available yet. Apple may request changes. No further signing password prompt is required by the prepared local update pipeline. Temporary Safari automation is disabled and the dedicated signing keychain is locked.

Source PR #6 is merged. All hosted native, Python, dependency-audit and brand checks pass: https://github.com/Somamill/listen/actions/runs/43529108895.

Signed-device iCloud continuation, background/audio route changes, Siri and authenticated third-party-account flows have not been certified end to end. Build/package validation and simulator tests do not establish those guarantees. Signing keys and API credentials stay private. Store packages contain the standard public signing certificate and provisioning information. Personal profiles, network settings, folders and audio libraries remain per user.

Store record: https://appstoreconnect.apple.com/apps/6834434329/distribution

## Separate desktop edition

The sandboxed Mac Store edition builds as `listen Player.app`, with bundle identifier `io.github.somamill.listen.mobile`. The existing desktop catalogue/torrent application remains separate, with its installation, library and qBittorrent routing unchanged.
