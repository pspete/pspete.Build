[CmdletBinding()]
param(
	[switch]$CodeCoverage,
	#Defaults to the repository root folder containing a manifest of the same name, e.g. 'AzCID/AzCID.psd1'
	[string]$ModuleName,
	#Expected manifest GUID; when omitted the GUID is only checked for presence
	[string]$ModuleGuid,
	#Repository root
	[string]$SourceFolder
)

#Scripts run from the repository root, which can differ from their own folder.
if (-not $SourceFolder) { $SourceFolder = (Get-Location).Path }

#---------------------------------#
# Header                          #
#---------------------------------#
Write-Host "Testing: PSVersion $($PSVersionTable.PSVersion)" -ForegroundColor Yellow

$RepoPath = $SourceFolder

#The checkout folder name varies by CI system (e.g. AppVeyor replaces dots with hyphens), so the module is found by its manifest.
if (-not $ModuleName) {

	$ModuleName = @(Get-ChildItem -Path $RepoPath -Directory | Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).psd1") }).Name

	if (@($ModuleName).Count -ne 1) {

		throw "Expected one module folder in $RepoPath, found $(@($ModuleName).Count); specify -ModuleName"

	}

}

$ModulePath = Join-Path $RepoPath $ModuleName
$ManifestPath = Join-Path $ModulePath "$ModuleName.psd1"

Import-Module Pester -RequiredVersion 5.7.1 -Force
Import-Module $ManifestPath -ArgumentList $true -Force

#---------------------------------#
# Run Pester Tests                #
#---------------------------------#
$configuration = [PesterConfiguration]::Default
#The generic module suite is location-independent, so it receives the module, tests and docs paths as data.
$SuiteData = @{
	ModulePath = $ModulePath
	TestsPath  = Join-Path $RepoPath 'Tests'
	DocsPath   = Join-Path $RepoPath 'docs/collections/_commands'
	Guid       = $ModuleGuid
}
$configuration.Run.Container = @(
	New-PesterContainer -Path (Join-Path $RepoPath 'Tests')
	New-PesterContainer -Path (Join-Path $PSScriptRoot 'tests/Module.Tests.ps1') -Data $SuiteData
)
$configuration.Run.PassThru = $true
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputFormat = 'JUnitXml'
$configuration.TestResult.OutputPath = Join-Path $RepoPath 'TestResults.xml'
$configuration.Output.Verbosity = 'Minimal'

if ($CodeCoverage) {

	$configuration.CodeCoverage.Enabled = $true
	$configuration.CodeCoverage.Path = Get-ChildItem $ModulePath -Include *.ps1 -Recurse | Select-Object -ExpandProperty FullName
	$configuration.CodeCoverage.OutputFormat = 'JaCoCo'
	$configuration.CodeCoverage.OutputPath = Join-Path $RepoPath 'coverage.xml'

}

$result = Invoke-Pester -Configuration $configuration

#---------------------------------#
# Upload Coverage & Test Results  #
#---------------------------------#
#CODECOV_TOKEN is a secret and may be absent (e.g. pull requests from forks); an unmapped Azure Pipelines
#secret reaches the script as the literal macro text '$(CODECOV_TOKEN)', so both cases skip the upload.
if ($CodeCoverage -and $env:CODECOV_TOKEN -and ($env:CODECOV_TOKEN -notlike '$(*')) {

	Write-Host 'Publishing Code Coverage'

	Push-Location $RepoPath

	try {
		$ProgressPreference = 'SilentlyContinue'
		$null = Invoke-WebRequest -Uri 'https://cli.codecov.io/latest/windows/codecov.exe' -OutFile codecov.exe
		.\codecov.exe --disable-telem upload-process --disable-search --fail-on-error -t "$env:CODECOV_TOKEN" -f coverage.xml
		.\codecov.exe --disable-telem do-upload --disable-search --fail-on-error -t "$env:CODECOV_TOKEN" --report-type test_results -f TestResults.xml
	} catch {
		Write-Warning "Code coverage upload failed: $_"
	} finally {
		Remove-Item -Path .\codecov.exe -Force -ErrorAction SilentlyContinue
		Pop-Location
	}

}

#---------------------------------#
# Validate                        #
#---------------------------------#
if (($result.Result -ne 'Passed') -or ($result.PassedCount -eq 0)) {

	throw "$($result.FailedCount) tests failed, $($result.FailedContainersCount) containers failed."

} else {

	Write-Host 'All tests passed' -ForegroundColor Green

}
