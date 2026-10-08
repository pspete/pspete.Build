#Requires -Modules Pester, PSScriptAnalyzer
<#
.SYNOPSIS
    Tests module for consistency, expected structures, settings, components & files.
.EXAMPLE
    $Container = New-PesterContainer -Path ./build/tests/Module.Tests.ps1 -Data @{ ModulePath = './AzCID'; TestsPath = './Tests'; DocsPath = './docs/collections/_commands' }
    Invoke-Pester -Container $Container
.NOTES
    A generic set of tests to apply to a module
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Parameters are used inside Pester script blocks')]
param(
	#Module folder containing <ModuleName>.psd1, source or built layout
	[Parameter(Mandatory)]
	[string]$ModulePath,
	#Folder expected to contain a <FunctionName>.Tests.ps1 file per exported function
	[Parameter(Mandatory)]
	[string]$TestsPath,
	#Folder expected to contain a <FunctionName>.md help file per exported function
	[Parameter(Mandatory)]
	[string]$DocsPath,
	#Expected manifest GUID; when omitted the GUID is only checked for presence
	[string]$Guid
)

Describe 'Module' -Tag 'Consistency' {

	$ModulePath = (Resolve-Path $ModulePath).Path
	$ModuleName = Split-Path $ModulePath -Leaf
	$Here = $TestsPath

	#Define Path to Module Manifest
	$ManifestPath = Join-Path "$ModulePath" "$ModuleName.psd1"

	#Reimporting would orphan the module instance that other containers' InModuleScope blocks bound to at discovery.
	$Module = Get-Module -Name $ModuleName | Where-Object { $_.ModuleBase -eq $ModulePath } | Select-Object -First 1

	if (-not $Module) {

		Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction Ignore

		$Module = Import-Module -Name "$ManifestPath" -ArgumentList $true -Force -ErrorAction Stop -PassThru |
			Where-Object { $_.Name -eq $ModuleName }

	}

	#Get Public Function Names
	#The built module is a single concatenated psm1 with no Public folder, so fall back to the manifest export list.
	$PublicPath = Join-Path "$ModulePath" 'Public'
	if (Test-Path $PublicPath) {
		$PublicFunctions = Get-ChildItem $PublicPath -Include *.ps1 -Recurse | Select-Object -ExpandProperty BaseName
	} else {
		$PublicFunctions = (Import-PowerShellDataFile -Path $ManifestPath).FunctionsToExport
	}

	#Get Exported Function Names
	$ExportedFunctions = $Module.ExportedFunctions.Values.name

	$ExportedAliases = $Module.ExportedAliases.Values.name

	$Scripts = Get-ChildItem $ModulePath -Include *.ps1, *.psm1 -Recurse

	Context $ManifestPath -Tag Manifest {

		It 'has a valid manifest' -TestCases @{ManifestPath = $ManifestPath } {
			param($ManifestPath)
			{ $null = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop -WarningAction SilentlyContinue } |
				Should -Not -Throw

		}

		It 'specifies valid root module' -TestCases @{RootModule = $Module.RootModule ; ModuleName = $ModuleName } {
			param($RootModule, $ModuleName)
			$RootModule | Should -Be "$ModuleName.psm1"

		}

		It 'has a valid description' -TestCases @{Description = $Module.Description } {
			param($Description)
			$Description | Should -Not -BeNullOrEmpty

		}

		It 'has a valid guid' -TestCases @{ModuleGuid = $Module.Guid ; Guid = $Guid } {
			param($ModuleGuid, $Guid)
			$ModuleGuid | Should -Not -Be ([guid]::Empty)
			if ($Guid) { $ModuleGuid | Should -Be $Guid }

		}

		It 'has a valid copyright' -TestCases @{Copyright = $Module.Copyright } {
			param($Copyright)
			$Copyright | Should -Not -BeNullOrEmpty

		}

		Context 'Files To Process' -Tag 'FilesToProcess' {

			foreach ($file in ($Module.ExportedFormatFiles)) {
				Context $file -Tag 'FormatData' {
					It 'exists' -TestCases @{
						'File' = $file
					} {
						param($File)
						$File | Should -Exist
					}

					It 'is valid' -TestCases @{
						'File' = $file
					} {
						param($File)
						{ Update-FormatData -AppendPath $File -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Not -Throw
					}

				}

				foreach ($file in ($Module.ExportedTypeFiles)) {
					Context $file -Tag 'TypeData' {
						It 'exists' -TestCases @{
							'File' = $file
						} {
							param($File)
							$File | Should -Exist
						}

						It 'is valid' -TestCases @{
							'File' = $file
						} {
							param($File)
							{ Update-TypeData -AppendPath $File -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Not -Throw
						}

					}
				}
			}
		}

		Context 'Exported Function Analysis' -Tag 'Functions' {

			It 'exports the expected number of functions' {

				($PublicFunctions | Measure-Object | Select-Object -ExpandProperty Count) |

					Should -Be ($ExportedFunctions | Measure-Object | Select-Object -ExpandProperty Count)

			}

			foreach ($ExportedFunction in $ExportedFunctions) {

				Context "$ExportedFunction" -Tag "$ExportedFunction" {
					It 'is public' -TestCases @{
						'ExportedFunction' = $ExportedFunction
						'PublicFunctions'  = $PublicFunctions
					} {
						param($ExportedFunction, $PublicFunctions)
						$PublicFunctions | Should -Contain $ExportedFunction
					}

					It 'has a related pester tests file' -TestCases @{
						'ExportedFunction' = $ExportedFunction
						'Here'             = $here
					} {
						param($ExportedFunction, $here)
						Test-Path (Join-Path $here "$ExportedFunction.Tests.ps1") | Should -Be $true
					}

					$MarkdownPath = Join-Path $DocsPath "$ExportedFunction.md"

					It 'has a help markdown file' -TestCases @{ 'MarkdownPath' = $MarkdownPath } {
						param($MarkdownPath)
						$MarkdownPath | Should -Exist
					}

					#New-MarkdownCommandHelp stubs mark text still to be written with {{ ... }}.
					It 'has no help markdown placeholders' -TestCases @{ 'MarkdownPath' = $MarkdownPath } {
						param($MarkdownPath)
						if (Test-Path $MarkdownPath) {
							(Select-String -Path $MarkdownPath -Pattern '\{\{.*?\}\}' | ForEach-Object { "line $($_.LineNumber): $($_.Line.Trim())" }) -join [System.Environment]::NewLine |
								Should -BeNullOrEmpty
						}
					}

					Context Help -Tag 'Help' {

						$help = Get-Help $ExportedFunction -Full

						It 'has synopsis' -TestCases @{ 'Help' = $help } {
							param($help)
							$help.synopsis | Should -Not -BeNullOrEmpty

						}

						It 'has description' -TestCases @{ 'Help' = $help } {
							param($help)
							$help.description | Should -Not -BeNullOrEmpty

						}

						#PlatyPS 1.x places example code in the introduction rather than the code element.
						It 'has example code' -TestCases @{ 'Help' = $help } {
							param($help)
							$help.examples.example | ForEach-Object { $_.code; $_.introduction.Text } |
								Where-Object { $_ -match '\S' } | Should -Not -BeNullOrEmpty

						}

						[array]$HelpParameters = $help.parameters.parameter | Where-Object name -NotIn @('WhatIf', 'Confirm')

						$CommonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters +
						[System.Management.Automation.PSCmdlet]::OptionalCommonParameters

						[array]$CommandParameters = (Get-Command $ExportedFunction).Parameters.Keys | Where-Object { $_ -notin $CommonParameters }

						foreach ($HelpParameter in $HelpParameters) {

							It 'has description of parameter <name>' -Tag "$($HelpParameter.name)" -TestCases @{
								'description' = $HelpParameter.description
								'name'        = $HelpParameter.name
							} {
								param($description, $name)
								$description | Should -Not -BeNullOrEmpty
							}

							It 'has function parameter for help parameter <name>' -Tag "$($HelpParameter.name)" -TestCases @{
								'CommandParameters' = $CommandParameters
								'name'              = $HelpParameter.name
							} {
								param($CommandParameters, $name)
								$CommandParameters | Should -Contain $name
							}

						}

						foreach ($CommandParameter in $CommandParameters) {

							It 'has help for function parameter <name>' -Tag "$CommandParameter" -TestCases @{
								'HelpParameters' = $HelpParameters.name
								'name'           = $CommandParameter
							} {
								param($HelpParameters, $name)
								$HelpParameters | Should -Contain $name
							}

						}

					}
				}

			}

		}

		Context 'Exported Alias Analysis' -Tag Alias {

			foreach ($Alias in $ExportedAliases) {

				It '<Alias> resolves to public function' -Tag $Alias -TestCases @{
					'Alias'           = $Alias
					'PublicFunctions' = $PublicFunctions
				} {
					param($Alias, $PublicFunctions)
					$PublicFunctions | Should -Contain $((Get-Alias $Alias).ResolvedCommand.Name)
				}

			}

		}

	}

	Context 'PSScriptAnalyzer Analysis' -Tag 'PSScriptAnalyzer' {

		#One analyzer pass per file (all Warning/Error rules at once), one It block per file - this
		#keeps It count to one-per-file while still naming the exact rule/line on failure.
		Foreach ($Script in $scripts) {

			Context $Script.Name -Tag "$($Script.BaseName)", "$($Script.Name)" {

				It 'passes all Warning and Error rules' -TestCases @{
					'FilePath' = $script.FullName
				} {
					param($FilePath)

					$findings = Invoke-ScriptAnalyzer -Path $FilePath -Severity Warning, Error

					($findings | ForEach-Object { "[$($_.RuleName)] line $($_.Line): $($_.Message)" }) -join [System.Environment]::NewLine |
						Should -BeNullOrEmpty

				}

			}

		}

	}

}
