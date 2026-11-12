# Release conventions

Each app retains its own version and release schedule. Use MAJOR.MINOR.PATCH and Git tags `vMAJOR.MINOR.PATCH`; pre-release tags may append `-beta.1` or another SemVer identifier. Major changes break compatibility, minor releases add compatible features, and patches fix compatible behavior. Keep platform build numbers separate.

New changelog entries use `## [version] - YYYY-MM-DD` with any relevant sections: Added, Changed, Fixed, Security. Explain observable user outcomes. Keep an Unreleased section for pending changes. Preserve historical entries and existing tooling; migrate formatting when adding the next entry.

Before publishing: run the app's own lint, type checks, tests and build checks where applicable, plus the shared dot. brand check. Keep Mac packaging, architecture matrices, Apple signing, notarization, iPhone preview and TestFlight steps in their existing repositories. A kit-only documentation/asset sync does not require an app version bump; visible UI or behavior changes do.

Keep Immersed's existing version:update and version:check process. Never synchronize app version numbers just because they share the dot. identity.
