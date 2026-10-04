[CmdletBinding()]
param(
	[Parameter(Mandatory)]
	[string]$ModuleName,
	[Parameter(Mandatory)]
	[string]$BuildVersion,
	[Parameter(Mandatory)]
	[string]$OutputFolder,
	[string]$SourceFolder
)

#Scripts run from the repository root, which can differ from their own folder.
if (-not $SourceFolder) { $SourceFolder = (Get-Location).Path }

$ErrorActionPreference = 'Stop'

#---------------------------------#
# Header                          #
#---------------------------------#
Write-Host 'Build Information:' -ForegroundColor Yellow

$SourcePath = (Resolve-Path -Path (Join-Path $SourceFolder $ModuleName)).Path
$ManifestPath = Join-Path $SourcePath "$ModuleName.psd1"
$CurrentVersion = (Import-PowerShellDataFile $ManifestPath).ModuleVersion
$ModuleVersion, $Prerelease = $BuildVersion -split '-', 2
$OutputPath = Join-Path $OutputFolder $ModuleName

Write-Host "ModuleName       : $ModuleName"
Write-Host "Build version    : $BuildVersion"
Write-Host "Manifest version : $CurrentVersion"
Write-Host "Source           : $SourcePath"
Write-Host "Output           : $OutputPath"

If ([System.Version]$ModuleVersion -le [System.Version]$CurrentVersion) {

	throw 'Build Version Not Greater than Current Version'

}

#Files are written as UTF-8 with BOM so Windows PowerShell reads non-ASCII content correctly and Authenticode signatures remain valid.
$Encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true

$null = New-Item -ItemType Directory -Path $OutputPath -Force

#---------------------------------#
# Module manifest                 #
#---------------------------------#
Write-Host "Updating Manifest Version to $BuildVersion" -ForegroundColor Cyan

$Manifest = [System.IO.File]::ReadAllText($ManifestPath).Replace("= '$CurrentVersion'", "= '$ModuleVersion'")

If ($Prerelease) {

	#The PSData Prerelease key is set, uncommented or added at the top of PSData.
	$PrereleasePattern = '(?m)^([ \t]*)#?[ \t]*Prerelease[ \t]*=[ \t]*''[^'']*'''
	$PSDataPattern = '(?m)^([ \t]*)PSData[ \t]*=[ \t]*@\{'
	If ($Manifest -match $PrereleasePattern) {
		$Manifest = [regex]::Replace($Manifest, $PrereleasePattern, "`${1}Prerelease = '$Prerelease'")
	} ElseIf ($Manifest -match $PSDataPattern) {
		$Manifest = [regex]::Replace($Manifest, $PSDataPattern, "`$0`n`${1}    Prerelease = '$Prerelease'")
	} Else {
		throw "$ManifestPath has no PSData section for Prerelease '$Prerelease'"
	}

}

[System.IO.File]::WriteAllText((Join-Path $OutputPath "$ModuleName.psd1"), $Manifest, $Encoding)

#---------------------------------#
# Combine module scripts          #
#---------------------------------#
Write-Host 'Combining Module Scripts' -ForegroundColor Cyan

#ScriptsToProcess files (e.g. class definitions) run in the caller's scope before import, so they are copied rather than combined.
$ScriptsToProcess = @(
	(Import-PowerShellDataFile $ManifestPath).ScriptsToProcess |
		Where-Object { $_ } |
		ForEach-Object { (Resolve-Path -Path (Join-Path $SourcePath $_)).Path }
)

$LoaderPath = Join-Path $SourcePath "$ModuleName.psm1"
$LoaderPattern = '(?s)#region Loader.*?#endregion Loader'
$Loader = [System.IO.File]::ReadAllText($LoaderPath)

If ($Loader -notmatch $LoaderPattern) {

	throw "$LoaderPath has no '#region Loader' ... '#endregion Loader' block"

}

$Content = @(
	foreach ($Folder in 'Private', 'Public') {

		Get-ChildItem -Path (Join-Path $SourcePath $Folder) -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue |
			Where-Object { $_.FullName -notin $ScriptsToProcess } |
			Sort-Object -Property FullName |
			ForEach-Object { [System.IO.File]::ReadAllText($_.FullName).Trim() }

	}
	([regex]::Replace($Loader, $LoaderPattern, '')).Trim()
) | Where-Object { $_ }

[System.IO.File]::WriteAllText((Join-Path $OutputPath "$ModuleName.psm1"), (($Content -join "`r`n`r`n") + "`r`n"), $Encoding)

#---------------------------------#
# Copy module resources           #
#---------------------------------#
Write-Host 'Copying Module Resources' -ForegroundColor Cyan

Get-ChildItem -Path $SourcePath -File -Recurse |
	Where-Object { $_.Extension -notin '.ps1', '.psm1', '.psd1' -or $_.FullName -in $ScriptsToProcess } |
	ForEach-Object {

		$Destination = Join-Path $OutputPath $_.FullName.Substring($SourcePath.Length + 1)
		$null = New-Item -ItemType Directory -Path (Split-Path -Path $Destination -Parent) -Force
		Copy-Item -Path $_.FullName -Destination $Destination -Force
		Write-Host "`t$($_.FullName.Substring($SourcePath.Length + 1))"

	}

Get-ChildItem -Path $OutputPath -File -Recurse | Select-Object -ExpandProperty FullName
