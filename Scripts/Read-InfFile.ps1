<#PSScriptInfo
.VERSION 2019.03.05
.GUID f6e1f1c3-064b-4748-8762-6eb623c2b274
.AUTHOR Chad McCaffery
.LICENSEURI https://unlicense.org
.PROJECTURI https://github.com/ChadMcCaffery/MiscPowershell
.REQUIREDSCRIPTS Read-IniFile.ps1
#>
<#
.DESCRIPTION
    Reads an INF file and returns an object containing the parsed sections and entries.
#>
[CmdletBinding()]
param(
    # Path to the .inf file
    [Parameter(Mandatory)]
    [string] $Path,

    # Specifies the target architecture to use for processing
    [ValidateSet("AMD64","IA64","X86","ARM64")]
    [string] $TargetArchitecture = ${Env:PROCESSOR_ARCHITECTURE},

    # Specifies the major and minor Windows version to use for processing
    [version] $TargetWindowsVersion = '10.0',

    # Specified the language code identifier (LCID) to use for language-specific string checks
    [int] $LCID,

    # Adds debugging information to the returned object
    [switch] $AddDebugInfo
)

$ReadIniFileCommand = Get-Command -Name Read-IniFile -ErrorAction Ignore
if ($null -eq $ReadIniFileCommand) {
    $thisScript = Join-Path -Path $PSScriptRoot -ChildPath $MyInvocation.ScriptName
    $uri = (Test-PSScriptFileInfo -Path $thisScript -ErrorAction Ignore).Link
}

filter Remove-ExtraWhitespace {$_ -replace '^["\s]*|["\s]*$',''}
filter ConvertTo-FlatCollection {$_ | Remove-ExtraWhitespace | ForEach-Object {$_ -split '\s*,\s*'}}

function ReplaceTokens([string] $text) {
    while ($text -match '\%([^%]+)\%') {
        $tokenName = $Matches[1]
        if ($StringTable.$tokenName) {
            $pattern = "%{0}%" -f [regex]::Escape($tokenName)
            $newText = $text -replace $pattern, $StringTable.$tokenName
            if ($newText -eq $text) { break }
            $text = $newText
        }
        else {
            break
        }
    }
    $text
}

function AddDebugStringValue([object] $object, [string] $key, [string] $value) {
    if ($AddDebugInfo) {
        if ($object.$key) {
            $object.$key += '/'
        }
        $object.$key += $value
    }
}

function GetScopedSection([string] $baseName) {
    $pattern = "(?:^{0}$|^{0}\.NT$|^{0}\.NT$TargetArchitecture$|^{0}\.NT$TargetArchitecture\.(?=\d).*$)" -f [regex]::Escape($baseName)
    $iniObject.GetEnumerator() | 
        Where-Object Name -Match $pattern | 
        Where-Object {
            [version] $osv = '6.0'

            # <name>.NT[Architecture][.[OSMajorVersion][.[OSMinorVersion][.[ProductType][.SuiteMask]]]]
            if ($_.Name.Length -gt $baseName.Length) {
                ($arch, $maj, $min, $typ, $suite) = $_.Name.Substring($baseName.Length + 1) -split '\.(?:NT)?'
                if ($maj -and $min) {
                    $osv = [version]::Parse("$maj.$min")
                }
            }

            if ($osv -le $TargetWindowsVersion) {
                $_ | Add-Member -MemberType NoteProperty -Name 'TargetOSVersion' -Value $osv
                $true
            }
        } |
        Sort-Object -Descending -Property TargetOSVersion, Name |
        Select-Object -First 1 -Property Name, Value

}

function GetScopedValue([object] $sectionObject, [string] $baseName) {
    $fields = @(
        $baseName,
        'NT',
        $TargetArchitecture
    )

    for ([int] $i=$fields.Count-1; $i -ge 0; $i--) {
        $valueName = $fields[0..$i] -join '.' -replace '(?<=\.)NT\.(\w+)', 'NT$1'
        if ($sectionObject.ContainsKey($valueName)) {
            New-Object psobject -Property @{
                Name = $valueName
                Value = $(ReplaceTokens $sectionObject.$valueName)
            }
            break
        }
    }
}

<#
[Version]

Signature="signature-name"
[Class=class-name]
[ClassGuid={nnnnnnnn-nnnn-nnnn-nnnn-nnnnnnnnnnnn}]
[Provider=%INF-creator%]
[LayoutFile=filename.inf [,filename.inf]... ]  (Windows 2000 and Windows XP)
[CatalogFile=filename.cat]
[CatalogFile.nt=unique-filename.cat]
[CatalogFile.ntx86=unique-filename.cat]
[CatalogFile.ntia64=unique-filename.cat]  (Windows XP and later versions of Windows)
[CatalogFile.ntamd64=unique-filename.cat]  (Windows XP and later versions of Windows)
DriverVer=mm/dd/yyyy[,w.x.y.z]
[DontReflectOffline=1] (Windows Vista and later versions of Windows)
[PnpLockDown=0|1] (Windows Vista and later versions of Windows)
[DriverPackageDisplayName=%driver-package-description%]
[DriverPackageType=PackageType]
#>
function DriverInfoFactory {
    $dv = (ReplaceTokens $iniObject.Version.DriverVer) | ConvertFrom-Csv -Header 'Date','Version'
    New-Object psobject -Property @{
        Class = ReplaceTokens $iniObject.Version.Class
        ClassGuid = (ReplaceTokens $iniObject.Version.ClassGuid) -as [guid]
        CatalogFile = $(GetScopedValue $iniObject.Version 'CatalogFile').Value
        Devices = @() -as [psobject[]]
        DriverPackageDisplayName = ReplaceTokens $iniObject.Version.DriverPackageDisplayName
        Errors = @() -as [string[]]
        Provider = ReplaceTokens $iniObject.Version.Provider
        PnpLockdown = $iniObject.Version.PnpLockdown -as [int]
        SourceFiles = @() -as [psobject[]]
        Version = $dv.Version -as [version]
        VersionDate = $dv.Date -as [DateTime]
    }
}

<#
[SourceDisksNames] |
[SourceDisksNames.x86] | 
[SourceDisksNames.ia64] | (Windows XP and later versions of Windows)
[SourceDisksNames.amd64] (Windows XP and later versions of Windows)

1000 = %QcomSrcDisk%,"",,\ndis\6.2\amd64

diskid = disk-description[,tag-or-cab-file] |

diskid = disk-description[
    ,[tag-or-cab-file]  
    [
    ,[unused]
    [,path]
    ]
]

diskid = disk-description[
    ,[tag-or-cab-file]
    ,[unused]
    ,[path]
    [,flags]
]

diskid = disk-description[
    ,[tag-or-cab-file]
    ,[unused]
    ,[path]
    ,[flags]
    [,tag-file]
]
#>
    function SourceDiskEntry([int] $diskId, [string] $csvText) {
        ($description, $tagOrCabFile, $unused, $subdir, $flags, $tagFile) = ($csvText | Remove-ExtraWhitespace) -split '\s*,\s*'
        New-Object psobject -Property @{
            DiskId = $diskId
            Description = $(ReplaceTokens $description)
            TagOrCabFile = $(ReplaceTokens $tagOrCabFile)
            Subdirectory = $(ReplaceTokens $subdir)
            Flags = $flags
            TagFile = $(ReplaceTokens $tagFile)
        }
    }

<#
[SourceDisksFiles] | 
[SourceDisksFiles.x86] | 
[SourceDisksFiles.ia64] | (Windows XP and later versions of Windows)
[SourceDisksFiles.amd64] (Windows XP and later versions of Windows)

filename=diskid[,[ subdir][,size]]
#>

function SourceFileEntry([string] $fileName, [string] $csvText) {
    ($diskId, $subdir, $size, $xtra) = $($csvText | Remove-ExtraWhitespace) -split '\s*,\s*',4

    # Order of Precedence
    #    FILE           DISK
    # 1. cpu            cpu
    # 2. cpu            gen
    # 3. gen            cpu
    # 4. gen            gen

    $diskInfo = $DiskTable[$diskId] -as [psobject]
    
    New-Object psobject -Property @{
        DiskInfo = $diskInfo
        Subdirectory = $(ReplaceTokens $subdir)
        UncompressedSize = $(if ($size) {[int]::Parse($size)} else {$null})
        FileName = $fileName
        FileAction = ''       # Copy, Rename, Delete
        DestinationDirectory = ''
        SourceDirectory = $(
            # Full path = 
            #   <inf directory>\<disk subdir>\<file subdir>\<file>
            $infPath | 
                Split-Path -Parent | 
                Join-Path -ChildPath $diskInfo.Subdirectory | 
                Join-Path -ChildPath $(ReplaceTokens $subdir)
        )
    }
}


## MAIN ##

try {
    $cultureInfo = [System.Globalization.CultureInfo]::GetCultureInfo($LCID)
}
catch { }
finally {
    if ($cultureInfo) {
        $lcidHex = '{0:x4}' -f $cultureInfo.LCID
    }
}    

$processedSections = @()
$infPath = Convert-Path -Path $Path
$iniObject = . $ReadIniFileCommand -Path $infPath

$StringTable = @{
    '65535' = ''
    '-1' = ''
    '01' = $(Split-Path -Parent $infPath)
    '10' = '%SystemRoot%'
    '11' = '%SystemRoot%\system32'
    '12' = '%SystemRoot%\system32\drivers'
    '17' = '%SystemRoot%\INF'
    '18' = '%SystemRoot%\Help'
    '20' = '%SystemRoot%\Fonts'
    '21' = '%SystemRoot%\Viewers'
    '23' = '%_ColorDir%'
    '24' = '%_SystemDiskRoot%'
    '25' = '%_SharedDir%'
    '30' = '%_BootDiskRootDir%'
    '50' = '%SystemRoot%\system'
    '51' = '%SystemRoot%\system32\spool'
    '52' = '%_SpoolDriversDir%'
    '53' = '%USERPROFILE%'
    '54' = '%_OsLoaderDir%'
    '55' = '%_PrintProcessorsDir%'
}

<#
[Strings] | 
[Strings.LanguageID] ...

strkey1 = ["]some string["]
strkey2 = "    string-with-leading-or-trailing-whitespace     "  | 
            "very-long-multiline-string" | 
            "string-with-semicolon" | 
            "string-ending-in-backslash" |
            ""double-quoted-string-value""
    ...
#>
# [Strings] (neutral)
foreach ($key in $iniObject.Strings.Keys) {
    $StringTable[$key] = $iniObject.Strings.$key | Remove-ExtraWhitespace
}

# [Strings.<lcid>] (language specific)
foreach ($key in $iniObject."Strings.$lcidHex".Keys) {
    $StringTable[$key] = $iniObject."Strings.$lcidHex".$key | Remove-ExtraWhitespace
}

$DiskTable = @{}

# [SourceDisksNames] (all architectures)
if ($iniObject.SourceDisksNames) {
    foreach ($diskItem in $iniObject.SourceDisksNames.GetEnumerator()) {
        $key = ReplaceTokens $diskItem.Name
        $DiskTable[$key] = SourceDiskEntry $key $iniObject.SourceDisksNames.$key
    }
}

# [SourceDisksNames.<arch>] (target architecture)
if ($iniObject."SourceDisksNames.$TargetArchitecture") {
    foreach ($diskItem in $iniObject."SourceDisksNames.$TargetArchitecture".GetEnumerator()) {
        $key = ReplaceTokens $diskItem.Name
        $DiskTable[$key] = SourceDiskEntry $key $iniObject."SourceDisksNames.$TargetArchitecture".$key
    }
}

$DestDirsTable = @{}
if ($iniObject.DestinationDirs) {
    foreach ($dirItem in $iniObject.DestinationDirs.GetEnumerator()) {
        $key = ReplaceTokens $dirItem.Name
        ($dirId, $subdir, $xtra) = $dirItem.Value -split '\s*,\s*',3

        $DestDirsTable[$key] = Join-Path -Path (ReplaceTokens "%$dirId%") -ChildPath $subdir
    }
}

## Create result object ##

$resultObject = DriverInfoFactory

# Compose the complete file list, using ALL files within [SourceDisksFiles.<arch>] section
# plus files within [SourceDisksFiles] section that weren't already found in the 
# architecture-specific section.

foreach ($key in $iniObject."SourceDisksFiles.$TargetArchitecture".Keys) {
    $resultObject.SourceFiles += $(SourceFileEntry $key $(
        $iniObject."SourceDisksFiles.$TargetArchitecture".$key | Sort-Object -Descending | Select-Object -First 1
    ))
}
foreach ($key in $iniObject.SourceDisksFiles.Keys) {
    # Only process the ones we haven't done yet
    if ($key -notin $resultObject.SourceFiles.FileName) {
        $resultObject.SourceFiles += $(SourceFileEntry $key $(
            $iniObject.SourceDisksFiles.$key | Sort-Object -Descending | Select-Object -First 1
        ))
    }
}

<#
[Manufacturer]

manufacturer-identifier
[manufacturer-identifier] 
[manufacturer-identifier] 
...
#>
if (-not $iniObject.Manufacturer) {
    $resultObject.Errors += "[Manufacturer] section not found"
    break
}
if ($iniObject.Manufacturer.Keys.Count -eq 0) {
    $resultObject.Errors += "[Manufacturer] section is empty"
    break
}

# manufacturer=model-section ...
foreach ($modelItem in $iniObject.Manufacturer.GetEnumerator()) {
    $debugFields = @{}
    AddDebugStringValue $debugFields '_InfProcessing' "[Manufacturer]/$($modelItem.Name)"
    $manufacturer = ReplaceTokens $modelItem.Name
    ($modelSectionName, $modelOSTargets, $xtra) = (ReplaceTokens $modelItem.Value) -split '\s*,\s*',3

    #region [model-section]
    $modelSectionObject = GetScopedSection $modelSectionName
    if ($modelSectionObject.Name -in $processedSections) {continue}

    AddDebugStringValue $debugFields '_InfProcessing' "[$($modelSectionObject.Name)]"

    if ($modelSectionObject -eq $null) {
        $resultObject.Errors += "[$modelSectionName] not found"
        continue
    }
    if ($modelSectionObject.Value.Keys.Count -eq 0) {
        $resultObject.Errors += "Device not applicable for Windows $TargetWindowsVersion / $TargetArchitecture - [$($modelSectionObject.Name)] is empty"
        continue
    }

    <#
    [install-section-name] | 
    [install-section-name.nt] | 
    [install-section-name.ntx86] | 
    [install-section-name.ntia64] |  (Windows XP and later versions of Windows)
    [install-section-name.ntamd64]  (Windows XP and later versions of Windows)

    [DriverVer=mm/dd/yyyy[,x.y.v.z] ]
    [CopyFiles=@filename | file-list-section[,file-list-section] ...]
    [CopyINF=filename1.inf[,filename2.inf]...]   (Windows XP and later versions of Windows)
    [AddReg=add-registry-section[,add-registry-section]...]
    [AddProperty=add-registry-section[,add-registry-section]...]  (Windows Vista and later versions of Windows)
    [Include=filename1.inf[,filename2.inf]...]
    [Needs=inf-section-name[,inf-section-name]...]
    [Delfiles=file-list-section[,file-list-section]...]
    [Renfiles=file-list-section[,file-list-section]...]
    [DelReg=del-registry-section[,del-registry-section]...]
    [DelProperty=add-registry-section[,add-registry-section]...]  (Windows Vista and later versions of Windows)
    [FeatureScore=featurescore]...  (Windows Vista and later versions of Windows)
    [BitReg=bit-registry-section[,bit-registry-section]...]
    [LogConfig=log-config-section[,log-config-section]...]
    [ProfileItems=profile-items-section[,profile-items-section]...]  (Microsoft Windows 2000 and later versions of Windows)
    [UpdateInis=update-ini-section[,update-ini-section]...]
    [UpdateIniFields=update-inifields-section[,update-inifields-section]...]
    [Ini2Reg=ini-to-registry-section[,ini-to-registry-section]...]
    [RegisterDlls=register-dll-section[,register-dll-section]...]
    [UnregisterDlls=unregister-dll-section[,unregister-dll-section]...]
    [ExcludeID=device-identification-string[,device-identification-string]...]...  ((Windows XP and later versions of Windows)
    [Reboot]
    #>

    # device-name=install-section,hwid[,compatibleid ...]
    foreach ($deviceEntry in $modelSectionObject.Value.GetEnumerator()) {
        AddDebugStringValue $debugFields '_InfProcessing' $deviceEntry.Name

        $deviceName = ReplaceTokens $deviceEntry.Name
        foreach ($deviceInfo in $deviceEntry.Value) {
            ($ddInstallName, $hardwareId, $compatibleIds, $xtra) = $deviceInfo -split '\s*,\s*',4
            $compatibleIds = $compatibleIds | ConvertTo-FlatCollection

            $newDevice = New-Object psobject -Property @{
                Manufacturer = $manufacturer
                Description = $deviceName
                HardwareId = $hardwareId
                CompatibleIds = $compatibleIds
            }

            if ($AddDebugInfo) {
                $newDevice | Add-Member -MemberType NoteProperty -Name '_Debug' -Value $debugFields
            }
            $resultObject.Devices += $newDevice

            #region Installation sections
            $ddInstallSection = GetScopedSection $ddInstallName
            if ($ddInstallSection.Name -in $processedSections) {continue}

            $sections = @(
                # [<DDInstall>]
                $ddInstallSection,

                # [<DDInstall>.CoInstallers]
                $($iniObject.GetEnumerator() | Where-Object Name -eq $($ddInstallSection.Name + '.CoInstallers')),

                # [DefaultInstall]
                $($iniObject.GetEnumerator() | Where-Object Name -eq 'DefaultInstall')
            ) | Where-Object Value -ne $null

            # Process each installation section
            foreach ($section in $sections) {

                $section.Value.GetEnumerator() |
                    Where-Object Name -in @('CopyFiles','DelFiles','RenFiles') |
                    ForEach-Object {
                        $o = $_
                        $o.Value | ConvertTo-FlatCollection | 
                            Select-Object @{Name='Name'; Expression={$o.Name}}, 
                                @{Name='Value'; Expression={$_}},
                                @{Name='FileAction'; Expression={
                                    switch ($o.Name) {
                                        'CopyFiles' {
                                            'Copy'
                                            break
                                        }
                                        'DelFiles' {
                                            'Delete'
                                            break
                                        }
                                        'RenFiles' {
                                            'Rename'
                                            break
                                        }
                                        Default {
                                            # other directives are unsupported for now
                                            continue
                                        }
                                    }
                                }}
                            
                    } |
                    ForEach-Object {
                        $installEntry = $_
                        $fileAction = $installEntry.FileAction
                        # File or [section] ?
                        if ($installEntry.Value -match '^\@(?<file>.+)') {
                            $resultObject.SourceFiles | 
                                Where-Object FileName -eq $Matches.file |
                                ForEach-Object {
                                    $_.FileAction = $fileAction
                                    $_.DestinationDirectory = $DestDirsTable.DefaultDestDir
                                }
                        }
                        else {   
                            $fileDirectiveSection = GetScopedSection $installEntry.Value
                            # "Unnamed values" have no 'name=' prefix so are keyed by an empty string
                            # Allow PowerShell to unwind the array for us
                            if ($fileDirectiveSection) {

                                foreach ($directiveEntry in @($fileDirectiveSection.Value.'')) {
                                    ($fileName, $xtra) = $directiveEntry -split '\s*,\s*',2
                                    $resultObject.SourceFiles |
                                        Where-Object FileName -eq $fileName |
                                        ForEach-Object {
                                            $_.FileAction = $fileAction
                                            $ddir = $DestDirsTable.$($fileDirectiveSection.Name)
                                            if ($ddir) {
                                                $_.DestinationDirectory = $ddir
                                            }
                                            else {
                                                $_.DestinationDirectory = $DestDirsTable.DefaultDestDir
                                            }
                                        }
                                }
                            }
                        }
                    }

                $processedSections += $section.Name
            }
            #endregion (Installation sections)
        }
    }

    $processedSections += $modelSectionObject.Name
    #endregion (model section)
}

$resultObject

<#
.SYNOPSIS
    Returns an object representing the specified .INF file
.DESCRIPTION
    Reads an INF file and returns an object containing the parsed sections and entries.
.LINK
    https://github.com/ChadMcCaffery/MiscPowershell
#>