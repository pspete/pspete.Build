# pspete.Build

Shared build, test and release scripts for PowerShell modules. They don't depend on any CI platform: every input is a parameter, and only secrets come from environment variables.

## Usage

CI clones a release tag of this repository into `build/` in the module repository, then runs the scripts from the module repository root:

```shell
git clone --depth 1 --branch v1 https://github.com/pspete/pspete.Build build
```

```powershell
./build/install.ps1
./build/test.ps1 -CodeCoverage -ModuleGuid '<guid>'
```

`v1` always points to the latest `1.x.y` release. Breaking changes ship as `v2`. To test a change before release, clone a branch instead.

Scripts run on Windows PowerShell 5.1 and PowerShell 7. `-SourceFolder` defaults to the current folder (the module repository root).

## Module repository layout

| Path | Purpose |
| --- | --- |
| `<Module>/<Module>.psd1` | Manifest with an explicit `FunctionsToExport` list |
| `<Module>/<Module>.psm1` | Dev-time loader inside `#region Loader` / `#endregion Loader`; module scope code goes below it |
| `<Module>/Public/**/*.ps1`, `<Module>/Private/**/*.ps1` | One function per file |
| `<Module>/<files in ScriptsToProcess>` | Copied unchanged, e.g. class definitions |
| `Tests/<Function>.Tests.ps1` | One test file per exported function |
| `docs/collections/_commands/<Function>.md` | platyPS help markdown, compiled to external help |
| `CHANGELOG.md` | `## Unreleased` sets the next version and the release notes |

## Scripts

| Script | Purpose | Parameters |
| --- | --- | --- |
| `install.ps1` | Install Pester 5.7.1, PSScriptAnalyzer and PSResourceGet (Windows PowerShell 5.1) | |
| `help.ps1` | Compile `docs/collections/_commands` to `<Module>/en-US/<Module>-help.xml` | `ModuleName` |
| `test.ps1` | Run `Tests/` and the generic module suite (`tests/Module.Tests.ps1`), write `TestResults.xml` (JUnit); `-CodeCoverage` writes `coverage.xml` (JaCoCo) and uploads to Codecov | `CodeCoverage`, `ModuleName`, `ModuleGuid` |
| `changelog.ps1` | Fail when `## Unreleased` is empty or `- N/A` (pull requests) | |
| `version.ps1` | Output the next version: `## Unreleased (major)` → major, `### Added` → minor, else patch; `-PrereleaseLabel` appends `<label><n>` | `ModuleName`, `PrereleaseLabel` |
| `build.ps1` | Combine functions into one `.psm1`, write the versioned manifest, copy resources | `ModuleName`, `BuildVersion`, `OutputFolder` |
| `deploy-github.ps1` | Commit the version, CHANGELOG, external help and release notes post `[skip ci]`; create the GitHub Release | `ModuleName`, `Version`, `Branch`, `Repository`, `ModulePath`, `ArchivePath`, `ReleaseVersionGate`, `GitUserName`, `ReleaseNotesPath` |
| `deploy-psgallery.ps1` | Verify the package, then publish it to the PowerShell Gallery | `ModuleName`, `Version`, `Branch`, `ModulePath`, `ReleaseVersionGate`, `CommitMessage` |
| `release-notes.ps1` | Write a release notes post for each major.minor version (called by `deploy-github.ps1`) | |
| `retry.ps1` | `Invoke-Retry`, dot-sourced for PowerShell Gallery calls | |

Stable releases deploy from `main` or `master`. Prereleases deploy from `vNext`.

## Secrets

| Variable | Used by |
| --- | --- |
| `CODECOV_TOKEN` | `test.ps1 -CodeCoverage` (upload skipped when unset) |
| `access_token` | `deploy-github.ps1`: GitHub token with Contents read/write |
| `github_email` | `deploy-github.ps1`: commit author email |
| `psgallery_key` | `deploy-psgallery.ps1` |
