<#PSScriptInfo
.VERSION 2019.03.05
.GUID 746aec38-d4b1-4161-a17c-0ec03d921a1f
.AUTHOR Chad McCaffery
.LICENSEURI https://unlicense.org
.PROJECTURI https://github.com/ChadMcCaffery/MiscPowershell
#>
<#
.DESCRIPTION
    Reads INI-style files and returns a hashtable where each [section] is a
    top-level key whose value is another hashtable of name=value pairs
#>
param(
    [Parameter(Mandatory)]
    [string] $Path
)

$fileContent = Get-Content -Path $Path

$ResultObject = @{}
$sectionName = ""
$ResultObject[$sectionName] = @{}
$sectionObject = $ResultObject[$sectionName]
$entryValue = $null

switch -regex ($fileContent) {
    # Empty lines
    '^\s*$' {
        # Save multiline entry value
        if ($entryValue) {
            $sectionObject[$entryName] += $entryValue
            $entryValue = $null
            $entryName = $null    # Empty lines reset the entry being saved
        }
        continue
    }

    # Skip comment lines
    '^\s*[;#].*$' { continue }

    # Grab sections
    '^\s*\[\s*([^\]]+?)\s*\]' {
        # Save multiline entry value
        if ($entryValue) {
            $sectionObject[$entryName] += $entryValue
            $entryValue = $null
            $entryName = $null
        }

        $sectionName = $Matches[1]

        # Look for existing section so additional entries can be appended
        $sectionObject = $ResultObject[$sectionName]

        # Create a new section
        if (-not ($sectionObject)) {
            $ResultObject[$sectionName] = @{}
            $sectionObject = $ResultObject[$sectionName]
        }

        continue
    }

    # Named values
    '^\s*([^\=]+?)\s*=\s*(.*)' {
        $tmpName = $Matches[1] -replace '^"|"$', ''
        $tmpValue = $Matches[2] -replace '(\s+|\s*[;#].*)$', ''

        # Are we building on a previous value?
        if ($entryValue) {
            $sectionObject[$entryName] += $entryValue
            $entryValue = $null
            $entryName = $null
        }

        $entryName = $tmpName 
        $entryValue = $null

        if ($sectionObject[$entryName] -eq $null) {
            $sectionObject[$entryName] = [string[]] @()
        }

        if ($tmpValue -match '\\$') {
            $entryValue = ($tmpValue -replace '\\$', '')
            continue
        }

        $entryValue = $tmpValue
        $sectionObject[$entryName] += $entryValue
        $entryValue = $null

        continue
    }

    # Unnamed values
    '^\s*(.+)' {
        $line = $Matches[1] -replace '(\s+|\s*[;#].*)$', ''

        # Are we building on a previous value?
        if ($entryValue) {
            $entryValue += ($line -replace '\\$', '')

            # Append current line to previous value
            if ($line -notmatch '\\$') {
                # Save multiline entry value
                $sectionObject[$entryName] += $entryValue
                $entryValue = $null
                $entryName = $null
            }
            continue
        }

        # Create new value
        $entryName = ""
        $entryValue = $line

        if ($sectionObject[$entryName] -eq $null) {
            $sectionObject[$entryName] = [string[]] @()
        }

        if ($entryValue -match '\\$') {
            $entryValue = ($line -replace '\\$', '')
            continue
        }
        $sectionObject[$entryName] += $entryValue
        $entryValue = $null

        continue
    }
}

$ResultObject

<#
.SYNOPSIS
    Returns objects from the contents of INI-style configuration files
.DESCRIPTION
    Reads INI-style files and returns a hashtable where each [section] is a
    top-level key whose value is another hashtable of name=value pairs.
.LINK
    https://github.com/ChadMcCaffery/MiscPowershell
#>
