<#---------------------------------
Output the next module version, from the source manifest (last released version) and CHANGELOG.md '## Unreleased':
- '## Unreleased (major)'      - major, e.g. 2.5.7 -> 3.0.0
- '### Added' under Unreleased - minor, e.g. 2.5.7 -> 2.6.0
- anything else                - patch, e.g. 2.5.7 -> 2.5.8
With -PrereleaseLabel, the next unpublished '<label><n>' of that version on the PSGallery is appended, e.g. 2.6.0-preview3.
---------------------------------#>
[CmdletBinding()]
param(
	#Module name, e.g. 'AzCID'
	[Parameter(Mandatory)]
	[string]$ModuleName,
	#Prerelease label, letters only, e.g. 'preview'; empty for a stable version
	[ValidatePattern('^[A-Za-z]*$')]
	[string]$PrereleaseLabel,
	#Repository root
	[string]$SourceFolder
)

#Scripts run from the repository root, which can differ from their own folder.
if (-not $SourceFolder) { $SourceFolder = (Get-Location).Path }

$ManifestPath = Join-Path (Join-Path $SourceFolder $ModuleName) "$ModuleName.psd1"
$Current = [version](Import-PowerShellDataFile -Path $ManifestPath).ModuleVersion

$ChangelogPath = Join-Path $SourceFolder 'CHANGELOG.md'
$Changelog = [System.IO.File]::ReadAllText($ChangelogPath)
$Unreleased = [regex]::Match($Changelog, '(?ms)^## Unreleased([ \t]+\(major\))?[ \t]*\r?\n(.*?)(?=^## |\z)')

If (-not $Unreleased.Success) {

	throw "$ChangelogPath has no '## Unreleased' section"

}

If ($Unreleased.Groups[1].Success) {

	$Bump = 'major'
	$Next = [version]::new($Current.Major + 1, 0, 0)

} ElseIf ($Unreleased.Groups[2].Value -match '(?m)^### Added[ \t]*\r?$') {

	$Bump = 'minor'
	$Next = [version]::new($Current.Major, $Current.Minor + 1, 0)

} Else {

	$Bump = 'patch'
	$Next = [version]::new($Current.Major, $Current.Minor, [math]::Max($Current.Build, 0) + 1)

}

$Next = $Next.ToString()

If ($PrereleaseLabel) {

	$Pattern = "^$PrereleaseLabel(\d+)$"
	. (Join-Path $PSScriptRoot 'retry.ps1')
	#A failed lookup must stop the run: an empty result would repeat an already published prerelease number.
	$Published = Invoke-Retry {
		try {
			Find-PSResource -Name $ModuleName -Version '*' -Prerelease -Repository PSGallery -ErrorAction Stop
		} catch {
			if ($_.FullyQualifiedErrorId -notlike 'PackageNotFound,*') { throw }
		}
	} |
		Where-Object { $_.Version.ToString(3) -eq $Next -and $_.Prerelease -match $Pattern } |
		ForEach-Object { [int]($_.Prerelease -replace $Pattern, '$1') }
	$Next = "$Next-$PrereleaseLabel$(($Published | Measure-Object -Maximum).Maximum + 1)"

}

Write-Host "Version: $Current -> $Next ($Bump)" -ForegroundColor Cyan

$Next
