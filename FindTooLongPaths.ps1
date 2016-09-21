$RawOffendingPaths = cmd /c dir /s /b |? {$_.length -gt 260}
$OffendingPaths = @()
ForEach ($Path in $RawOffendingPaths ) { 
    $CutPath = $Path.replace((Get-Location),"")
    $OffendingPaths += New-Object -TypeName PSObject -Property @{
        Path = $CutPath -as [string]
        Length = $CutPath.length -as [int]
    }
}
$OffendingPaths | Sort-Object -Property Length -Descending | Out-GridView -Title ($OffendingPaths.Count.ToString() + " Offending Paths in " + (Get-Location))
