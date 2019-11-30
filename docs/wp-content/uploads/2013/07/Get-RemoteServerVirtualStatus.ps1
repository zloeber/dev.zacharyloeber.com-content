Function Get-RemoteServerVirtualStatus
{
    <#
    .SYNOPSIS
        Validate if a remote server is virtual or physical
    .DESCRIPTION
        Uses wmi (along with an optional credential) to determine if a remote computers, or list of remote computers are virtual.
        If found to be virtual, a best guess effort is done on which type of virtual platform it is running on.
    .PARAMETER ComputerName
        Computer or IP address of machine
    .PARAMETER PromptForCredential
        Set this if you want the function to prompt for alternate credentials.
    .PARAMETER Credential
        Provide an alternate credential
    .EXAMPLE
        $Credential = Get-Credential
        Get-RemoteServerVirtualStatus 'Server1','Server2' -Credential $Credential | select ComputerName,IsVirtual,VirtualType | ft
        
        Description:
        ------------------
        Using an alternate credential, determine if server1 and server2 are virtual. Return the results along with the type of virtual machine it might be.
    .EXAMPLE
        (Get-RemoteServerVirtualStatus server1).IsVirtual
        
        Description:
        ------------------
        Determine if server1 is virtual and returns either true or false.

    .LINK
        http://zacharyloeber.com/
    .LINK
        http://nl.linkedin.com/in/zloeber
    .NOTES
        
        Name       : Get-RemoteServerVirtualStatus
        Version    : 1.0.0 07/27/2013
                     - First release
        Author     : Zachary Loeber
        Disclaimer : This script is provided AS IS without warranty of any kind. I 
                     disclaim all implied warranties including, without limitation,
                     any implied warranties of merchantability or of fitness for a 
                     particular purpose. The entire risk arising out of the use or
                     performance of the sample scripts and documentation remains
                     with you. In no event shall I be liable for any damages 
                     whatsoever (including, without limitation, damages for loss of 
                     business profits, business interruption, loss of business 
                     information, or other pecuniary loss) arising out of the use of or 
                     inability to use the script or documentation. 

        Copyright  : I believe in sharing knowledge, so this script and its use is 
                     subject to : http://creativecommons.org/licenses/by-sa/3.0/
    #>
    [cmdletBinding(SupportsShouldProcess = $true)]
    param(
        [parameter( Position=0,
                    Mandatory=$true,
                    ValueFromPipeline=$true,
                    HelpMessage="Computer or IP address of machine to test")]
        [string[]]$ComputerName,
        [parameter( HelpMessage="Set this if you want the function to prompt for alternate credentials.")]
        [switch]$PromptForCredential,
        [parameter( HelpMessage="Pass an alternate credential")]
        [System.Management.Automation.PSCredential]$Credential = $null
    )
    BEGIN
    {
        if ($PromptForCredential)
        {
            $Credential = Get-Credential
        }
        $WMISplat = @{}
        if ($Credential -ne $null)
        {
            $WMISplat.Credential = $Credential
        }
    }
    PROCESS
    {
        $results = @()
        $computernames = @()
        $computernames += $ComputerName
        
        foreach($computer in $computernames)
        {
            $WMISplat.ComputerName = $computer
            try
            {
                $wmibios = Get-WmiObject Win32_BIOS @WMISplat -ErrorAction Stop | Select-Object version,serialnumber
                $wmisystem = Get-WmiObject Win32_ComputerSystem @WMISplat -ErrorAction Stop | Select-Object model,manufacturer
                $CanConnect = $true
            }
            catch
            {
                $CanConnect = $false
            }
            if ($CanConnect)
            {
                $ResultProps = @{ 
                    ComputerName = $computer
                    BIOSVersion = $wmibios.Version
                    SerialNumber = $wmibios.serialnumber
                    Manufacturer = $wmisystem.manufacturer
                    Model = $wmisystem.model
                    IsVirtual = $false
                    VirtualType = $null
                }
                if ($wmibios.Version -match "VIRTUAL") 
                {
                    $ResultProps.IsVirtual = $true
                    $ResultProps.VirtualType = "Virtual - Hyper-V"
                }
                elseif ($wmibios.Version -match "A M I") 
                {
                    $ResultProps.IsVirtual = $true
                    $ResultProps.VirtualType = "Virtual - Virtual PC"
                }
                elseif ($wmibios.Version -like "*Xen*") 
                {
                    $ResultProps.IsVirtual = $true
                    $ResultProps.VirtualType = "Virtual - Xen"
                }
                elseif ($wmibios.SerialNumber -like "*VMware*")
                {
                    $ResultProps.IsVirtual = $true
                    $ResultProps.VirtualType = "Virtual - VMWare"
                }
                elseif ($wmisystem.manufacturer -like "*Microsoft*")
                {
                    $ResultProps.IsVirtual = $true
                    $ResultProps.VirtualType = "Virtual - Hyper-V"
                }
                elseif ($wmisystem.manufacturer -like "*VMWare*")
                {
                    $ResultProps.IsVirtual = $true
                    $ResultProps.VirtualType = "Virtual - VMWare"
                }
                elseif ($wmisystem.model -like "*Virtual*")
                {
                    $ResultProps.IsVirtual = $true
                    $ResultProps.VirtualType = "Unknown Virtual Machine"
                }
                $results += New-Object PsObject -Property $ResultProps
            }
            else
            {
                Write-Warning "Cannot connect to $computer"
            }
        }
    }
    END
    {
        return $results
    }
}