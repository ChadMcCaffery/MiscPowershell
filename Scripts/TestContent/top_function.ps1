<# 
a bunch of comments go here
 #>

begin {
    function Test-FirstFunction {}

<# 
a bunch of comments go here
 #>

 function Test-InsideStartBlock {}
}

process {
    function Test-InsideProcessBlock {}
<# 
a bunch of comments go here
 #>

}

end {
    function Test-InsideEndBlock {}
<# 
a bunch of comments go here
 #>

 function Test-LastFunction {}
}