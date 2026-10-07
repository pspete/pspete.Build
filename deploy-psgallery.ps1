<#---------------------------------
Auto-publish changes to main or master branch as a new module version in the PSGallery.
A prerelease version (e.g. 1.3.0-preview1) publishes from branch vNext.
- Only publish if build version is greater than or equal to ReleaseVersionGate
- Skip Auto-publish with specific commit message of "Manual Deployment"
- Skip when the version is already on the PSGallery (re-run of a failed release)

Requires this secret as an environment variable:
  psgallery_key         - PowerShell Gallery API key
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
	#Packaged module folder, e.g. '<workspace>/Package/AzCID/1.2.9'
	[Parameter(Mandatory)]
	[string]$ModulePath,
	#Lowest version that publishes, e.g. '0.1.0' for a new module, or '1.0.0' once past initial development
	[Parameter(Mandatory)]
	[string]$ReleaseVersionGate,
	#Commit message of the triggering commit; 'Manual Deployment' skips publishing
	[string]$CommitMessage
)

$ModuleVersion, $Prerelease = $Version -split '-', 2

$ReleaseBranches = if ($Prerelease) { 'vNext' } else { 'main', 'master' }

If (($Branch -in $ReleaseBranches) -and ([version]$ModuleVersion -ge [version]$ReleaseVersionGate)) {

	Write-Host 'Deploy Process: PowerShell Gallery' -ForegroundColor Yellow

	If ($CommitMessage -eq 'Manual Deployment') {

		<# Manual Deploy to PSGallery #>
		Write-Host "Finished testing of branch: $Branch" -ForegroundColor Cyan
		Write-Host 'Manual Deployment to PSGallery Required' -ForegroundColor Cyan
		Write-Host 'Exiting' -ForegroundColor Cyan
		exit

	}

	#A re-run of a failed release finds the version already published.
	. (Join-Path $PSScriptRoot 'retry.ps1')
	$Published = Invoke-Retry {
		try {
			Find-PSResource -Name $ModuleName -Version $Version -Prerelease:([bool]$Prerelease) -Repository PSGallery -ErrorAction Stop
		} catch {
			if ($_.FullyQualifiedErrorId -notlike 'PackageNotFound,*') { throw }
		}
	}

	If ($Published) {

		Write-Host "$ModuleName $Version already published to PSGallery; skipped." -ForegroundColor Cyan
		exit 0

	}

	<#---------------------------------#
	# Package & Verify                 #
	#----------------------------------#>

	$ModulePath = Resolve-Path $ModulePath

	#The package is published to a temporary local repository, installed from it and imported;
	#the same nupkg is then published to the PSGallery.
	#RequiredModules are not in the temporary repository, so its dependency checks are skipped;
	#Import-Module still needs them installed.
	$TempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
	$RepoFolder = Join-Path $TempFolder 'repo'
	$SaveFolder = Join-Path $TempFolder 'save'
	$TempRepository = "$ModuleName-Verify"
	$null = New-Item -ItemType Directory -Path $RepoFolder, $SaveFolder -Force

	Write-Host "Verify $ModuleName $Version package......" -NoNewline

	Try {

		Register-PSResourceRepository -Name $TempRepository -Uri $RepoFolder -Trusted -ErrorAction Stop
		Publish-PSResource -Path $ModulePath -Repository $TempRepository -SkipDependenciesCheck -ErrorAction Stop
		$NupkgPath = Join-Path $RepoFolder "$ModuleName.$Version.nupkg"

		Save-PSResource -Name $ModuleName -Version $Version -Prerelease:([bool]$Prerelease) -Repository $TempRepository -Path $SaveFolder -TrustRepository -SkipDependencyCheck -ErrorAction Stop
		$Manifest = Join-Path (Join-Path (Join-Path $SaveFolder $ModuleName) $ModuleVersion) "$ModuleName.psd1"
		$Data = Import-PowerShellDataFile -Path $Manifest
		$Expected = @($Data.FunctionsToExport)

		#PassThru also returns a module per ScriptsToProcess script.
		$Imported = Import-Module -Name $Manifest -Force -PassThru -ErrorAction Stop
		$Module = $Imported | Where-Object { $_.Name -eq $ModuleName }
		$Exported = @($Module.ExportedFunctions.Keys)
		Remove-Module -ModuleInfo $Imported -Force

		If ($Module.Version -ne [version]$ModuleVersion -or $Data.PrivateData.PSData.Prerelease -ne $Prerelease) {
			throw "Package version $($Module.Version) prerelease '$($Data.PrivateData.PSData.Prerelease)' does not match $Version"
		}
		$Missing = $Expected | Where-Object { $_ -notin $Exported }
		If ($Missing -or ($Exported.Count -ne $Expected.Count)) {
			throw "Exported functions ($($Exported -join ', ')) do not match FunctionsToExport ($($Expected -join ', '))"
		}

		Write-Host 'OK' -ForegroundColor Green

	} Catch {

		Write-Host "Failed - $_." -ForegroundColor Red
		Remove-Item -Path $TempFolder -Recurse -Force -ErrorAction SilentlyContinue
		throw $_

	} Finally {

		Unregister-PSResourceRepository -Name $TempRepository -ErrorAction SilentlyContinue

	}

	<#---------------------------------#
	# Publish to PS Gallery            #
	#----------------------------------#>

	Write-Host "Publish $ModuleName $Version to Powershell Gallery......" -NoNewline

	Try {

		Publish-PSResource -NupkgPath $NupkgPath -Repository PSGallery -ApiKey $env:psgallery_key -Confirm:$false -ErrorAction Stop

		Write-Host 'OK' -ForegroundColor Green

	} Catch {

		Write-Host "Failed - $_." -ForegroundColor Red
		throw $_

	} Finally {

		Remove-Item -Path $TempFolder -Recurse -Force -ErrorAction SilentlyContinue

	}

} Else {

	<# No Deployment      #>

	Write-Host "Finished testing: $ModuleName $Branch ($Version) - Exiting" -ForegroundColor Cyan

}
