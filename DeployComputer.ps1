$ErrorActionPreference = "SilentlyContinue"

<#
	    .SYNOPSIS
		    Deploys new PC using standards
	
	    .DESCRIPTION
		    Builds computer name off of conformity, creates AD Computer object via commands to remote PC, joins AD and optionally reboots.

	    .PARAMETERS
		    None
	
	    .NOTES
		    Function has only been tested on Win10. Function requires user input throughout.
#>

If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] “Administrator”))
{

    Write-Warning “You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator.”
    Pause
    exit

} else {

        function Build-ComputerName
        {
        # Get Site Code, $SiteCode, default to 'ABC'
        $SiteCode = Read-Host 'Input Site code: [ABC]'
        if ($SiteCode -eq $null -or $SiteCode -eq '') { $SiteCode = 'ABC' }

        # Get Building Number, $BuildingNumber, default to 01
        $BuildingNumber = Read-Host 'Input building number: [01]'
        if ($BuildingNumber -eq $null -or $BuildingNumber -eq '') { $BuildingNumber = '01' }

        # Get Computer Code, $ComputerCode, default to 'DT'
        $ComputerCode = Read-Host 'Input computer code: [DT]'
        if ($ComputerCode -eq $null -or $ComputerCode -eq '') { $ComputerCode = 'DT' }

        # Get Last 6 characters of Mac Address, $MacLast6, default to manual input if one is not detected
        $MacLast6 = ''
        try {
            $Mac = Get-WMIObject win32_networkadapter | Where-Object {$_.AdapterType -match "802.3"} | Select-Object MACAddress -Unique | ForEach {$_.MacAddress -replace ":",""}
            $lines = $Mac | Measure-Object -line
            if ($lines.Lines -ge 2) {
                Write-Error "Multiple ethernet devices detected."
                Write-Host -ForegroundColor Red "Error retreiving Mac Address! Displaying all adapters..."
                Get-NetAdapter | Out-Host
                $MacLast6 = Read-Host "Enter last 6 of desired Mac Address: (123456)"
            } else {$MacLast6 = $Mac.Substring(6)}
        } 
        catch {
            Write-Host -ForegroundColor Red "Error retreiving Mac Address! Displaying all adapters..."
            Write-Output | Get-NetAdapter
            $MacLast6 = Read-Host "Enter last 6 of desired Mac Address: (123456)"
        }

        # Generate Computer Name, $NewName
        $NewName = $SiteCode + $BuildingNumber + $ComputerCode + "-" + $MacLast6
        $NewName = $NewName.ToUpper()
        #Write-Host "Computer name set to '$NewName'."
        return $NewName
    }
        function Get-DellServiceTag
        {
                $SystemEnclosure = Get-WmiObject win32_SystemEnclosure
                $ServiceTag = $SystemEnclosure.SerialNumber
                $ServiceTag
         }
        function Build-DefaultAdministrator
        {
            Write-Host "Building root administrator."
            $ServiceTag = Get-DellServiceTag
            ([adsi]'WinNT://./admin123').SetPassword($password) > $null
            ([adsi]'WinNT://./Administrator').SetPassword($password) > $null
            $admin = [adsi]'WinNT://./Administrator,user' > $null
            $admin.psbase.Rename('admin123') > $null
            Write-Host "Root administrator built."
        }
        function Build-AdObjectDescription
        {
        $Date = Get-Date
        $Description = (Get-WmiObject -Class:Win32_ComputerSystem).Manufacturer + " " + (Get-WmiObject -Class:Win32_ComputerSystem).Model + " (WIN" + [System.Environment]::OSVersion.Version.Major + ") - Deployed on " + $Date + " by " + $AdminCredentials.Username
        #Write-Host -ForegroundColor Yellow "Device Description set to '$Description'"
        return $Description
    }
        function Select-OrganizationalUnit
        {
            [CmdletBinding()]Param(
                [Parameter(
                    Position    = 0
                )]
                $Credential = $AdminCredentials,
    
                [Parameter(
                    Position    = 1  
                )]
                [ValidateSet('domain.contoso.com','domain.contoso.com')]
                $Domain = 'domain.contoso.com'
            )

            # Use DNS SRV records to find a DC in the domain of choice.
            try {
                [array]$dcList = Resolve-DnsName -DnsOnly -Type SRV -Name "_ldap._tcp.$Domain" -ErrorAction STOP | Select-Object -ExpandProperty NameTarget
                Write-Verbose -Message ('Domain controllers found in {0}: {1}' -f $Domain,$dcList.count)
                [String]$dc = $dcList | Get-Random
                Write-Verbose -Message ('Using {0}' -f $dc)
            }
            catch {
                Write-Error -ErrorAction Stop -Message ('Unable to pick a domain controller in {0}: {1}' -f $Domain,$_.exception.message)
            }

            try {
               $bindPath = 'LDAP://{0}' -f $dc
               $domainBind = New-Object System.DirectoryServices.DirectoryEntry($bindPath,$Credential.UserName,$Credential.GetNetworkCredential().password,'Secure')
               $searcher = New-Object System.DirectoryServices.DirectorySearcher($domainBind)
               $searcher.Filter = '(objectClass=OrganizationalUnit)'
               [void]$searcher.PropertiesToLoad.Add('distinguishedname')
               $searcher.PageSize = 1500
               $ou = $searcher.FindAll() | ForEach-Object { $_.Properties.distinguishedname } | Sort-Object | Out-GridView -Title "Pick an OU" -OutputMode Single 
            }
            catch {
                Write-Error -ErrorAction STOP -Message ('Unable to find OUs in {0}: {1}' -f $Domain,$_.exception.message)
            }

            $ou
        }
        function Join-AD
        {
            $Path = ""
            $OU = ""
            $DN = ""
            $confirm = $FALSE
            while($confirm -eq $FALSE)
            {
                $OU = Select-OrganizationalUnit
                if ($OU) {
                    $confirm = Read-Host "Continue with '$OU'? ([y]/n)"
                    if ($confirm -eq $null -or $confirm -eq '') { $confirm = 'y' }
                    if($confirm.ToLower() -eq "y") { $confirm = $true } else { $confirm = $false }
                } else {
                    exit
                }
                
            }
            $DesiredOU = $OU
            $DesiredDN = 'CN=' + $NewName + ',' + $OU
            $Description = Build-AdObjectDescription
            Invoke-Command -ComputerName $RemoteAD -ScriptBlock {
                Param($NewName, $DesiredOU, $Description, $AdminCredentials); 
                try{
                    $ExistingADobject = Get-ADComputer $NewName -Credential $AdminCredentials -ErrorAction Stop
                    if ($DesiredDN -eq $ExistingADobject.DistinguishedName) {
                        Get-ADComputer $NewName | Set-ADComputer -Credential $AdminCredentials -Description $Description
                     } else {
                        Get-ADComputer $NewName | Move-ADObject -Credential $AdminCredentials -TargetPath $DesiredDN
                        Get-ADComputer $NewName | Set-ADComputer -Credential $AdminCredentials -Description $Description
                     }
                 }
                 catch{ 
                    New-ADComputer -Name $NewName -Path $DesiredOU -Description $Description -Credential $AdminCredentials
                 }
            } -ArgumentList $NewName, $DesiredOU, $Description, $AdminCredentials -Credential $AdminCredentials -Authentication Credss
           
            Add-Computer -Domain domain.contoso.com -Credential $AdminCredentials -Force
        }    
}
    $OldName = $env:computername
    $RemoteAD = "domainjoinedpc.domain.contoso.com"
    try {
        Write-Host "Setting up PowerShell Remoting..."
        Enable-PSRemoting -Force > $null
        set-item wsman:localhost\client\trustedhosts -Force -value * > $null
        Enable-WSManCredSSP -Force -Role Client –DelegateComputer *  > $null
        Write-Host "PowerShell Remoting setup complete."
    }
    catch {
        Write-Host -ForegroundColor Red "There was a problem setting up PowerShell Remoting!"
        pause
    }
    $AdminCredentials = Get-Credential contoso\ -Message 'Enter domain credentials.'
    Write-Host "Building object description."
    $Description = Build-AdObjectDescription
    $OSValues = Get-WmiObject -class Win32_OperatingSystem 
    $OSValues.Description = $Description 
    $OSValues.put() > $null
    Write-Host "Description built as '$description'."
    Write-Host "Building new object name."
    $NewName = Build-ComputerName
    (Get-WmiObject win32_computersystem).rename($NewName) > $null
    Rename-Computer -NewName $NewName -Force > $null
    Write-Host "Object name set to '$NewName'."
    Write-Host "Building 'admin123' account."
    Build-DefaultAdministrator
    Write-Host "Built 'admin123' account."
    Write-Host "Joining '$NewName' to domain 'domain.contoso.com'."
    Join-AD
    Write-Host "'$NewName' joined to domain 'domain.contoso.com'."

    $caption = "Post-Deployment Configuration Complete";
	$message = "Configuration has completed. Would you like to restart now?";
	$Yes = new-Object System.Management.Automation.Host.ChoiceDescription "&Yes","Yes";
	$No = new-Object System.Management.Automation.Host.ChoiceDescription "&No","No";
	$choices = [System.Management.Automation.Host.ChoiceDescription[]]($Yes,$No);
	$answer = $host.ui.PromptForChoice($caption,$message,$choices,0)

	if ($answer -eq 0) 
	{
         Restart-Computer -Force
    } else {
        pause
        exit
    }
