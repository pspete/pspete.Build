# Changelog

## Unreleased

### Fixed

- `deploy-psgallery.ps1` skips publishing when the version is already on the PSGallery, so a re-run of a release no longer fails with 409.
- `version.ps1 -PrereleaseLabel` also counts remote `v<version>-<label><n>` tags, so a `Manual Deployment` prerelease number is not reused. A tag on the checked out commit keeps its number, so re-runs keep the version.
- `deploy-github.ps1` tags a prerelease at the checked out commit instead of the branch head.

## [1.0.0] - 2026-10-04

### Added

- Build, test and release scripts, moved from `pspete/AzCID` `build/`.
- `-SourceFolder` defaults to the current folder, so the scripts run from a separate checkout.
