<#---------------------------------
Fail when CHANGELOG.md has no release notes under '## Unreleased'.
Intended for pull requests: every change that reaches a release needs a CHANGELOG entry.
---------------------------------#>
[CmdletBinding()]
param(
	#Repository root
	[string]$SourceFolder
)

#Scripts run from the repository root, which can differ from their own folder.
if (-not $SourceFolder) { $SourceFolder = (Get-Location).Path }

$ChangelogPath = Join-Path $SourceFolder 'CHANGELOG.md'
$Changelog = [System.IO.File]::ReadAllText($ChangelogPath)
$Unreleased = [regex]::Match($Changelog, '(?ms)^## Unreleased(?:[ \t]+\(major\))?[ \t]*\r?\n(.*?)(?=^## |\z)')

If (-not $Unreleased.Success) {

	throw "$ChangelogPath has no '## Unreleased' section"

}

$Notes = $Unreleased.Groups[1].Value.Trim()

If (-not $Notes -or $Notes -eq '- N/A') {

	throw "No release notes under '## Unreleased' in $ChangelogPath; describe the change there"

}

Write-Host 'CHANGELOG.md Unreleased notes:' -ForegroundColor Green
Write-Host $Notes
