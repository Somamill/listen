# Part of dot.

Shared source: https://github.com/Somamill/dot-brand-kit

`branding/dot/` is a vendored snapshot. Edit shared tokens, vector marks and guidelines in the source repository; the hourly `Sync dot. brand kit` workflow opens an update PR here. You can also run it manually from Actions. Review and merge updates independently. GitHub may delay scheduled runs and pauses schedules after 60 days of inactivity in public repositories.

Run `python3 branding/dot/check.py` for the shared brand check. Existing application CI and platform release workflows remain authoritative for builds and releases. Bot-created PRs validate the kit in their sync run; GITHUB_TOKEN does not trigger other PR workflows. Run app checks or push a human-authored commit before merging.

See `branding/dot/guidelines/identity.md`, `copy.md` and `releases.md`. Use independent SemVer app versions and `v` tags, with Added/Changed/Fixed/Security changelog sections for new entries. Keep existing release tools and historical entries. UI adoption and production platform icons require separate implementation; vendoring this directory alone does not alter product screens.

To refresh locally, clone the source repository and run `python3 scripts/sync-dot-brand.py /path/to/dot-brand-kit`. Review the source SHA and file hashes in `branding/dot/source.json`. The automated branch namespace `dot/brand-*` is reserved for these proposals; changes on those branches are preserved and never force-pushed.
