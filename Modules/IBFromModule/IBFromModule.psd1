@{
    RootModule        = 'IBFromModule.psm1'
    ModuleVersion     = '2021.1.9'
    GUID              = 'aa30720d-f785-4710-b651-e775e4a2313b'
    Author            = 'Chad McCaffery'
    CompanyName       = ''
    Copyright         = ''
    PowerShellVersion = '5.1'
    NestedModules     = @('InvokeBuild')
    FunctionsToExport = @('Build-MyThing')
    CmdletsToExport   = @()
    PrivateData       = @{
        PSData = @{
            # Tags = @()
            LicenseUri = 'https://unlicense.org/'
            ProjectUri = 'https://github.com/ChadMcCaffery/MiscPowershell'
        }
    }
}
