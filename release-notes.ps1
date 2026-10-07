<#---------------------------------
Write release notes for a stable version to a Jekyll post, one post per major.minor version:
- x.y.0 creates '<yyyy-MM-dd>-<modulename>-release-<x>-<y>.md'
- x.y.z adds a '## [x.y.z]' section at the top of the existing x.y post (created when missing),
  sets its date and version and adds new tags.
Tags are 'Release Notes' plus each exported function named in backticks in the notes.
Outputs the post path.
---------------------------------#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Commands', Justification = 'Used within the Where-Object script block')]
[CmdletBinding()]
param(
	#Module name, e.g. 'psPAS'
	[Parameter(Mandatory)]
	[string]$ModuleName,
	#Stable version, e.g. '8.1.44'
	[Parameter(Mandatory)]
	[version]$Version,
	#Release notes markdown
	[Parameter(Mandatory)]
	[string]$Notes,
	#Posts folder, e.g. '<repo>/docs/collections/_posts'
	[Parameter(Mandatory)]
	[string]$Path,
	#Exported function names
	[string[]]$Commands = @(),
	#Release date
	[datetime]$Date = (Get-Date).ToUniversalTime()
)

$Slug = "$($ModuleName.ToLower())-release-$($Version.Major)-$($Version.Minor)"
$PostDate = $Date.ToString('yyyy-MM-dd')
$Section = "## [$Version]`n`n$($Notes.Trim() -replace '\r\n', "`n")`n"

$Tags = @('Release Notes') + @(
	[regex]::Matches($Notes, '`([^`\s]+)`') |
		ForEach-Object { $_.Groups[1].Value } |
		Where-Object { $_ -in $Commands }
) | Select-Object -Unique

$null = New-Item -ItemType Directory -Path $Path -Force
$Post = Get-ChildItem -Path $Path -Filter "*-$Slug.md" -File | Sort-Object -Property Name | Select-Object -Last 1

If ($Post) {

	$Content = [System.IO.File]::ReadAllText($Post.FullName) -replace '\r\n', "`n"
	$FrontMatter = [regex]::Match($Content, '(?s)\A---\n(.*?)\n---\n')

	If (-not $FrontMatter.Success) {

		throw "$($Post.FullName) has no front matter"

	}

	$Header = [regex]::Replace($FrontMatter.Groups[1].Value, '(?m)^date:.*$', "date: $PostDate 00:00:00")
	If ($Header -match '(?m)^version:') {

		$Header = [regex]::Replace($Header, '(?m)^version:.*$', "version: $Version")

	} Else {

		$Header = [regex]::Replace($Header, '(?m)^(date:.*)$', "`$1`nversion: $Version")

	}
	$TagBlock = [regex]::Match($Header, '(?m)^tags:\n((?:[ \t]+-[ \t].*(?:\n|$))*)')

	$Existing = @(
		$TagBlock.Groups[1].Value -split '\n' |
			Where-Object { $_.Trim() } |
			ForEach-Object { ($_ -replace '^[ \t]+-[ \t]+').Trim() }
	)
	$Merged = @($Existing) + @($Tags | Where-Object { $_ -notin $Existing })
	$TagLines = (@('tags:') + @($Merged | ForEach-Object { "  - $_" })) -join "`n"

	If ($TagBlock.Success) {

		$Trailing = if ($TagBlock.Value.EndsWith("`n")) { "`n" } else { '' }
		$Header = $Header.Remove($TagBlock.Index, $TagBlock.Length).Insert($TagBlock.Index, "$TagLines$Trailing")

	} Else {

		$Header = "$Header`n$TagLines"

	}

	$Body = $Content.Substring($FrontMatter.Length).TrimStart("`n")
	$Content = "---`n$Header`n---`n`n$Section`n$Body"
	$PostPath = $Post.FullName

} Else {

	$Content = (@(
			'---'
			"title: `"$ModuleName Release $($Version.Major).$($Version.Minor)`""
			"date: $PostDate 00:00:00"
			"version: $Version"
			'tags:'
			$Tags | ForEach-Object { "  - $_" }
			'---'
			''
			$Section
		) -join "`n")
	$PostPath = Join-Path $Path "$PostDate-$Slug.md"

}

[System.IO.File]::WriteAllText($PostPath, $Content)

$PostPath
