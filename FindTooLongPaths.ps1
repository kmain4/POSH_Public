if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }
Write-Host "Starting file path length scanner..."
Add-Type -AssemblyName System.Windows.Forms
$FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
    SelectedPath = (Get-Location)
}
[void]$FolderBrowser.ShowDialog()
cd $FolderBrowser.SelectedPath
Write-Host ("Scanning " + (Get-Location) + " for file paths near 210 characters...")
$RawOffendingPaths = cmd /c dir /s /b |? {$_.length -gt 200}
$OffendingPaths = @()
ForEach ($Path in $RawOffendingPaths ) { 
    $CutPath = $Path.replace((Get-Location),"")
    $OffendingPaths += New-Object -TypeName PSObject -Property @{
        Path = $CutPath -as [string]
        Length = $CutPath.length -as [int]
    }
}
$OffendingPaths | Sort-Object -Property Length -Descending | Out-GridView -Title ($OffendingPaths.Count.ToString() + " Offending Paths in " + (Get-Location))
if ($OffendingPaths.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show("No offending files found." , "Search Complete") 
    }
