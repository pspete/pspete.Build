# Changelog

## [1.2.2] - 2026-10-08

### Fixed

- `deploy-psgallery.ps1` treats a 409 from the PSGallery publish (version already exists) as published, with a warning. A slow Gallery response after an accepted push no longer fails the release.

## [1.2.1] - 2026-10-07

### Fixed

- `deploy-psgallery.ps1` skips the dependency checks against its temporary verify repository, so a module with `RequiredModules` no longer fails with `Dependency '<name>' was not found in repository '<Module>-Verify'`.

## [1.2.0] - 2026-10-07

### Added

- `release-notes.ps1` writes `version: x.y.z` to the post front matter, and a patch updates it (adding it to an older post that lacks it).

## [1.1.0] - 2026-10-06

### Added

- `build.ps1` merges two or more `FormatsToProcess` files into `<Module>.Format.ps1xml`, and two or more `TypesToProcess` files into `<Module>.Types.ps1xml`, and points the built manifest entries at them. Fewer files cut module import time.

## [1.0.1] - 2026-10-04

### Fixed

- `deploy-psgallery.ps1` skips publishing when the version is already on the PSGallery, so a re-run of a release no longer fails with 409.
- `version.ps1 -PrereleaseLabel` also counts remote `v<version>-<label><n>` tags, so a `Manual Deployment` prerelease number is not reused. A tag on the checked out commit keeps its number, so re-runs keep the version.
- `deploy-github.ps1` tags a prerelease at the checked out commit instead of the branch head.

## [1.0.0] - 2026-10-04

### Added

- Build, test and release scripts, moved from `pspete/AzCID` `build/`.
- `-SourceFolder` defaults to the current folder, so the scripts run from a separate checkout.
