#=============================
# Copyright (c) 2024 Microsoft
#=============================

#.SYNOPSIS
#    Outside help, under top-of-file comment
#.NOTES
#    It seems it only finds it when there is whitespace
#    between the top-of-file comment and the help
function Test-OutsideHelpLinesUnderTopOfFileComment {
param()
}
<#
.SYNOPSIS
OH NO! This help is OUTSIDE of Test-OutsideHelpBlockExtraWhitespace!
.NOTES
Only found only when it has 0 or 1 blank lines between itself and the function
#>

function Test-OutsideHelpBlockExtraWhitespace { }

function Test-NoHelpComment { }

function Test-InsideHelpLines {
#.SYNOPSIS
#    Help is INSIDE of Test-InsideHelpLines
param ()
return $true
}

function Test-InsideHelpBlock {
<#
.SYNOPSIS
    This help is INSIDE of Test-InsideBlockComment!
#>
param()
$true
}

function Test-InsideHelpBlockAtBottom {
param()
$true
<#
.SYNOPSIS
Will this be found now?
.DESCRIPTION
    This help block as at the bottom of Test-InsideBlockCommentAtBottom!
#>
}

function Test-InsideHelpLinesWithoutSynopsis {
#
#.DESCRIPTION
# This has no synopsis, so PowerShell will not consider it a help comment
#.NOTES
# blah blah
#

}
