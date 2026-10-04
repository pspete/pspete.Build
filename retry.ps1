#Dot-sourced by build scripts that call the PowerShell Gallery.
function Invoke-Retry {
	<#
	.SYNOPSIS
	Runs a script block, retrying on terminating errors (e.g. PowerShell Gallery 5xx/time-outs).
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[scriptblock]$ScriptBlock,
		[int]$Attempts = 3,
		[int]$DelaySeconds = 15
	)

	for ($Attempt = 1; ; $Attempt++) {

		try {
			return & $ScriptBlock
		} catch {
			if ($Attempt -ge $Attempts) { throw }
			Write-Warning "Attempt $Attempt of $Attempts failed: $($_.Exception.Message) Retrying in $DelaySeconds seconds."
			Start-Sleep -Seconds $DelaySeconds
		}

	}

}
