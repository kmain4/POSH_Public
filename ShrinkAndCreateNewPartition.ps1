Function Hide-OSCDrive
{
<#
 	.SYNOPSIS
        Hide-OSCDrive is an advanced function which can be hide drive letter from explorer view.
    .DESCRIPTION
        Hide-OSCDrive is an advanced function which can be hide drive letter from explorer view.
    .PARAMETER  <DriveLetter>
		Specifies a or more drive letters you want to hide.
	.PARAMETER  <ShowAll>
		Displays all drives.
    .EXAMPLE
        C:\PS> Hide-OSCDrive -DriveLetter "D","E"
		
		This command will hide drive "D" and "E".
    .EXAMPLE
        C:\PS> Hide-OSCDrive -ShowAll
		
		This command will display all drives.
#>
	[CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName="__AllParameterSets")]
	Param
	(
		[Parameter(Mandatory=$true,ParameterSetName="Drive")]
		[Alias('d')][String[]]$DriveLetter,
		[Parameter(Mandatory=$false,ParameterSetName="AllDrives")]
		[Alias('all')][Switch]$ShowAll
	)
	
	Begin
	{
		$RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
	}
	
	Process
	{
		$RegDriveKey = (Get-ItemProperty -Path $RegPath).NoDrives
		If($DriveLetter)
		{
			Foreach($Drive in $DriveLetter)
			{
				$DriveNumber = [Int][Char]$Drive.ToUpper() - 65
				$Mask += [System.Math]::Pow(2,$DriveNumber)
				#Setting the value of registry property
				Set-ItemProperty -Path $RegPath -Name NoDrives -Value $Mask -Type DWORD
				Write-Warning "Drive:""$DriveLetter"" has been hidden successfully,it will take effect after you log off current user account."
			}
		}
		If($ShowAll)
		{
			If($RegDriveKey -ne $null)
			{
				#Display all drives
				Remove-ItemProperty -Path $RegPath -Name NoDrives
				Write-Warning "Setting successed,it will take effect after you log off current user account."
			}
			Else
			{
				Write-Warning "All drives has been displayed already."
			}
		}
	}	
}

Write-Host "Shrinking 'C:' by 100gb..."
Get-Partition -DriveLetter C | Resize-Partition -Size ((Get-Partition -DriveLetter C).Size - 100000000000) > Out-Null
Write-Host "Creating 'F:'..."
New-Partition -DiskNumber 0 -UseMaximumSize -DriveLetter F > Out-Null
Write-Host "Formatting 'F:'..."
Format-Volume -DriveLetter F -FileSystem NTFS -NewFileSystemLabel "SCCM Cache" > Out-Null
Write-Host "Hiding 'F:'..."
Hide-OSCDrive -DriveLetter F
