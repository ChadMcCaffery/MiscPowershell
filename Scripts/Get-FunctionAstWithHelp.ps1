<#
.SYNOPSIS
    Returns FunctionDefinitionAst objects for functions that have help comments

.EXAMPLE
    Get-FunctionAstWithHelp.ps1 -Path .\test_script.ps1 |
    Where { ![string]::IsNullOrWhiteSpace($_.Body.GetHelpContent()) }

    Find functions whose help content is defined outside of the function body
#>
[CmdletBinding()]
param (
    # Path to script file
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('Path')]
    $InputObject,

    # Include nested functions too
    [switch] $IncludeNested
)

begin {
    $IsFunctionDefWithHelp = [Func[Management.Automation.Language.Ast, bool]] {
        param([Management.Automation.Language.Ast] $ast)
        ($ast -is [Management.Automation.Language.FunctionDefinitionAst]) -and
        ($null -ne $ast.GetHelpContent())
    }
}

process {
    $path = Resolve-Path -Path $InputObject | Convert-Path
    $fileAst = [Management.Automation.Language.Parser]::ParseFile($path, [ref] $null, [ref] $null)
    if ($null -ne $fileast) {
        $fileAst.FindAll($IsFunctionDefWithHelp, $IncludeNested)
    }
}
