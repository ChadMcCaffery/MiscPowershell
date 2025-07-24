$script:ModuleVar = 'CAN YOU SEE ME?'

$IB = Get-Command -Name Invoke-Build

function Build-MyThing {
    &$IB -File $PSScriptRoot\.build.ps1
}
