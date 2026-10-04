#---------------------------------#
# Header                          #
#---------------------------------#
Write-Host 'Installing Required Modules:' -ForegroundColor Yellow

. (Join-Path $PSScriptRoot 'retry.ps1')

$RequiredModules = @(
	@{ Name = 'Pester'; Version = '5.7.1' }
	@{ Name = 'PSScriptAnalyzer' }
)

#---------------------------------#
# Install PSResourceGet           #
#---------------------------------#
#PowerShell 7.4+ ships PSResourceGet; Windows PowerShell 5.1 installs it with PowerShellGet.
if (-not (Get-Module -Name Microsoft.PowerShell.PSResourceGet -ListAvailable)) {
	Write-Host "`tInstalling: Microsoft.PowerShell.PSResourceGet..." -NoNewline
	$null = Invoke-Retry { Install-PackageProvider -Name NuGet -Confirm:$false -Force -ErrorAction Stop }
	Invoke-Retry { Install-Module -Name Microsoft.PowerShell.PSResourceGet -Repository PSGallery -Scope CurrentUser -Confirm:$false -Force -ErrorAction Stop }
	Write-Host ' OK' -ForegroundColor Green
}
Import-Module -Name Microsoft.PowerShell.PSResourceGet -ErrorAction Stop

#---------------------------------#
# Install Required Modules        #
#---------------------------------#
foreach ($Module in $RequiredModules) {

	try {
		Write-Host "`tInstalling: $($Module.Name)..." -NoNewline
		$InstallParams = @{
			Name            = $Module.Name
			Repository      = 'PSGallery'
			Scope           = 'CurrentUser'
			TrustRepository = $true
			Reinstall       = $true
			ErrorAction     = 'Stop'
		}
		if ($Module.Version) {
			$InstallParams.Version = $Module.Version
		}
		Invoke-Retry { Install-PSResource @InstallParams }
		Write-Host ' OK' -ForegroundColor Green
	} catch {
		Write-Host 'Error' -ForegroundColor Red
		throw $_
	}

}
