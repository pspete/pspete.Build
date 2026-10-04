<#---------------------------------
Update version number on GitHub to match build version, then create a GitHub Release with the module zip.
A prerelease version (e.g. 1.3.0-preview1) only creates a GitHub prerelease, from branch vNext; the source manifest and CHANGELOG.md stay unchanged.

Requires these secrets as environment variables:
  access_token          - GitHub token with Contents read/write
  github_email          - commit author email
---------------------------------#>
[CmdletBinding()]
param(
	#Module name, e.g. 'AzCID'
	[Parameter(Mandatory)]
	[string]$ModuleName,
	#Build version, e.g. '1.2.9' or '1.3.0-preview1'
	[Parameter(Mandatory)]
	[string]$Version,
	#Branch name without refs/heads/, e.g. 'main'
	[Parameter(Mandatory)]
	[string]$Branch,
	#GitHub repository as owner/name, e.g. 'pspete/AzCID'
	[Parameter(Mandatory)]
	[string]$Repository,
	#Packaged module folder, e.g. '<workspace>/Package/AzCID/1.2.9'
	[Parameter(Mandatory)]
	[string]$ModulePath,
	#Module zip to attach to the GitHub Release
	[Parameter(Mandatory)]
	[string]$ArchivePath,
	#Lowest version that creates a GitHub Release
	[Parameter(Mandatory)]
	[string]$ReleaseVersionGate,
	#Commit author name
	[Parameter(Mandatory)]
	[string]$GitUserName,
	#Release notes posts folder relative to the repository root, e.g. 'docs/collections/_posts'; empty for none
	[string]$ReleaseNotesPath,
	#Repository root
	[string]$SourceFolder
)

#Scripts run from the repository root, which can differ from their own folder.
if (-not $SourceFolder) { $SourceFolder = (Get-Location).Path }

$ModuleVersion, $Prerelease = $Version -split '-', 2

$ReleaseBranches = if ($Prerelease) { 'vNext' } else { 'main', 'master' }

If ($Branch -notin $ReleaseBranches) {

	Write-Host "$Branch Branch; No Release" -ForegroundColor Cyan
	exit

}

#Unreleased notes become the GitHub Release notes.
$ChangelogPath = Join-Path $SourceFolder 'CHANGELOG.md'
$Changelog = [System.IO.File]::ReadAllText($ChangelogPath)
$Unreleased = [regex]::Match($Changelog, '(?ms)^## Unreleased(?:[ \t]+\(major\))?[ \t]*\r?\n(.*?)(?=^## |\z)')
$ReleaseNotes = $null

if ($Unreleased.Success) {

	$Notes = $Unreleased.Groups[1].Value.Trim()
	if ($Notes -and $Notes -ne '- N/A') { $ReleaseNotes = $Notes }

}

$RemoteUrl = "https://$($env:access_token):x-oauth-basic@github.com/$Repository.git"
$Pushed = $false

If (-not $Prerelease) {

	#A re-run of a failed release finds the version commit already on the branch.
	Set-Location -Path $SourceFolder
	git fetch -q $RemoteUrl $Branch
	if ($LASTEXITCODE -ne 0) { throw "git fetch exited with code $LASTEXITCODE" }
	$RemoteManifest = (git show "FETCH_HEAD:$ModuleName/$ModuleName.psd1") -join "`n"
	$Pushed = $RemoteManifest -match "(?m)^\s*ModuleVersion\s*=\s*'$([regex]::Escape($Version))'"
	if ($Pushed) { Write-Host "$ModuleName $Version already on $Branch; version commit skipped." -ForegroundColor Cyan }

}

If (-not $Prerelease -and -not $Pushed) {

	Write-Host 'Deploy Process: GitHub Repository' -ForegroundColor Yellow

	<#---------------------------------#>
	<# Push source psd1 to branch      #>
	<#---------------------------------#>
	#The source manifest in the checkout is updated, not the packaged one, so the branch never receives a signed file.
	Try {

		$ManifestPath = Join-Path (Join-Path $SourceFolder $ModuleName) "$ModuleName.psd1"
		$Current = (Import-PowerShellDataFile $ManifestPath).ModuleVersion
		$Manifest = [System.IO.File]::ReadAllText($ManifestPath).Replace("= '$Current'", "= '$Version'")
		[System.IO.File]::WriteAllText($ManifestPath, $Manifest)

		#Unreleased notes move under a version heading; Unreleased resets to '- N/A' without a (major) marker.
		if ($ReleaseNotes) {

			$NewLine = if ($Changelog -match "`r`n") { "`r`n" } else { "`n" }
			$Date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
			$Section = (@('## Unreleased', '', '- N/A', '', "## [$Version] - $Date", '', $ReleaseNotes, '', '') -join $NewLine)
			$Changelog = $Changelog.Remove($Unreleased.Index, $Unreleased.Length).Insert($Unreleased.Index, $Section)
			[System.IO.File]::WriteAllText($ChangelogPath, $Changelog)

		}

		#External help generated during Build is copied from the released package; git only commits it when it differs.
		$HelpFile = Join-Path 'en-US' "$ModuleName-help.xml"
		$PackageHelpPath = Join-Path $ModulePath $HelpFile
		$HelpPath = Join-Path (Join-Path $SourceFolder $ModuleName) $HelpFile
		$CommitPaths = @($ManifestPath, $ChangelogPath)

		if (Test-Path $PackageHelpPath) {

			$null = New-Item -ItemType Directory -Path (Split-Path -Path $HelpPath -Parent) -Force
			Copy-Item -Path $PackageHelpPath -Destination $HelpPath -Force
			$CommitPaths += $HelpPath

		}

		#Release notes are written to a post per major.minor version (build/release-notes.ps1).
		if ($ReleaseNotesPath -and $ReleaseNotes) {

			$Commands = (Import-PowerShellDataFile (Join-Path $ModulePath "$ModuleName.psd1")).FunctionsToExport
			$CommitPaths += & (Join-Path $PSScriptRoot 'release-notes.ps1') -ModuleName $ModuleName -Version $Version -Notes $ReleaseNotes -Path (Join-Path $SourceFolder $ReleaseNotesPath) -Commands $Commands

		}

		Write-Host "Push Updated $ModuleName.psd1, CHANGELOG.md, external help and release notes to GitHub..." -ForegroundColor Yellow

		Set-Location -Path $SourceFolder

		git config --global core.safecrlf false
		git config --global user.email "$($env:github_email)"
		git config --global user.name "$GitUserName"

		git checkout -q -B $Branch

		git add $CommitPaths

		git status

		#[skip ci] prevents the version commit retriggering the pipeline.
		git commit -s -m "Update Version: $Version [skip ci]"

		git push --porcelain $RemoteUrl "HEAD:$Branch"
		if ($LASTEXITCODE -ne 0) { throw "git push exited with code $LASTEXITCODE" }

		Write-Host "$ModuleName version $Version pushed to GitHub." -ForegroundColor Cyan

	}

	Catch {

		Write-Host 'Push to GitHub failed.' -ForegroundColor Red
		throw $_

	}

}

Write-Host 'Deploy Process: GitHub Release' -ForegroundColor Yellow

If ([version]$ModuleVersion -ge [version]$ReleaseVersionGate) {

	<# Create New Release     #>

	$token = $env:access_token
	$uploadFilePath = Resolve-Path $ArchivePath
	$releaseName = "v$Version"

	$headers = @{
		'Authorization' = "token $token"
		'Content-type'  = 'application/json'
	}

	$body = @{
		tag_name         = $releaseName
		target_commitish = $Branch
		name             = $releaseName
		body             = if ($ReleaseNotes) { $ReleaseNotes } else { "$ModuleName v$Version" }
		draft            = $false
		prerelease       = [bool]$Prerelease
	}

	$ApiUrl = "https://api.github.com/repos/$Repository/releases"
	$assetName = [IO.Path]::GetFileName($uploadFilePath)

	try {

		#A re-run of a failed release reuses an existing release and skips an uploaded asset.
		try {
			$release = Invoke-RestMethod -Uri "$ApiUrl/tags/$releaseName" -Headers $headers -Method GET
			Write-Host "Release $releaseName exists." -ForegroundColor Cyan
		} catch {
			if ([int]$_.Exception.Response.StatusCode -ne 404) { throw }
			Write-Host "Creating release $releaseName..." -NoNewline
			$release = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -Method POST -Body (ConvertTo-Json $body)
			Write-Host 'OK' -ForegroundColor Green
		}

		if ($assetName -in @($release.assets.name)) {

			Write-Host "Asset $assetName exists." -ForegroundColor Cyan

		} else {

			Write-Host "Uploading asset $assetName..." -NoNewline

			$uploadUrl = $release.upload_url.Replace('{?name,label}', '') + '?name=' + $assetName
			$uploadHeaders = @{
				'Authorization' = "token $token"
			}

			$null = Invoke-RestMethod -Uri $uploadUrl -Headers $uploadHeaders -Method POST -InFile $uploadFilePath -ContentType 'application/octet-stream'
			Write-Host 'OK' -ForegroundColor Green

		}

	} catch {

		Write-Host 'GitHub Release Failed.' -ForegroundColor Red
		throw $_

	}

}
