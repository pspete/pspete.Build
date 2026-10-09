[CmdletBinding()]
param(
	[Parameter(Mandatory)]
	[string]$ModuleName,
	[string]$SourceFolder
)

#Scripts run from the repository root, which can differ from their own folder.
if (-not $SourceFolder) { $SourceFolder = (Get-Location).Path }

$ErrorActionPreference = 'Stop'

#---------------------------------#
# Header                          #
#---------------------------------#
Write-Host 'Update External Help:' -ForegroundColor Yellow

$MarkdownPath = Join-Path $SourceFolder 'docs/collections/_commands'
$HelpFolder = Join-Path (Join-Path $SourceFolder $ModuleName) 'en-US'
$HelpPath = Join-Path $HelpFolder "$ModuleName-help.xml"

#---------------------------------#
# Install PlatyPS                 #
#---------------------------------#
Write-Host "`tInstalling: Microsoft.PowerShell.PlatyPS..." -NoNewline
. (Join-Path $PSScriptRoot 'retry.ps1')
#A copy already in the CurrentUser scope (e.g. restored from a CI cache) is not downloaded again.
if (-not (Get-InstalledPSResource -Name Microsoft.PowerShell.PlatyPS -Scope CurrentUser -ErrorAction SilentlyContinue)) {
	Invoke-Retry { Install-PSResource -Name Microsoft.PowerShell.PlatyPS -Repository PSGallery -Scope CurrentUser -TrustRepository }
}
Import-Module -Name Microsoft.PowerShell.PlatyPS
Write-Host " OK ($((Get-Module Microsoft.PowerShell.PlatyPS).Version))" -ForegroundColor Green

#---------------------------------#
# Generate MAML                   #
#---------------------------------#
#Export-MamlCommandHelp writes to <OutputFolder>/<ModuleName>/<external help file>, so it is exported to a temporary folder and copied to a fixed path.
$TempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())

try {

	$Exported = Get-ChildItem -Path $MarkdownPath -Filter '*.md' -File |
		Import-MarkdownCommandHelp -Path { $_.FullName } |
		Export-MamlCommandHelp -OutputFolder $TempFolder -Force

	If (@($Exported).Count -ne 1) {

		throw "Expected one MAML file, got $(@($Exported).Count); check 'external help file' metadata in $MarkdownPath"

	}

	$null = New-Item -ItemType Directory -Path $HelpFolder -Force
	Copy-Item -Path $Exported.FullName -Destination $HelpPath -Force
	Write-Host "`t$HelpPath" -ForegroundColor Cyan

} finally {

	Remove-Item -Path $TempFolder -Recurse -Force -ErrorAction SilentlyContinue

}
