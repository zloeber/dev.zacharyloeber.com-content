function Get-RemoteDiskInformation
{
    <#
    .SYNOPSIS
        Gather remote disk information.
    .DESCRIPTION
        This function gathers information disks, their partitions, and any mount points on a server.
    .PARAMETER ComputerName
        Computer to connect to for registry values
    .PARAMETER PromptForCredential
        Set this if you want the function to prompt for alternate credentials
    .PARAMETER Credential
        Pass an alternate credential
    .EXAMPLE
        $cred = get-credential
        Get-RemoteDiskInformation -Computername @('Server-01','Server-02') -Credential $Cred | where {$_.DiskType -eq 'MountPoint'} | select Computer,Disk,Drive,PercentageFree,FreeSpace,DiskSize | ft -auto

        Description:
        ------------------
        Returns disk information about Server-01 and Server-02 using an alternate credential then filters out only the mount points.
    .EXAMPLE
        Get-RemoteDiskInformation

        Description:
        ------------------
        Returns disk information about the local computer using the current credentials.
    .NOTES
        Name       : Get-RemoteDiskInformation
        Version    : 1.0.0 June 24th 2013
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


    .LINK
        http://zacharyloeber.com/
    .LINK
        http://nl.linkedin.com/in/zloeber
    #>
    [CmdletBinding()]
    param(
    	[Parameter( Position=0,
                    ValueFromPipeline=$true,
                    HelpMessage="Computer to connect to for registry values" )]
    	[String[]]$ComputerName = $env:computername,
        [parameter( HelpMessage="Set this if you want the function to prompt for alternate credentials")]
        [bool]$PromptForCredential = $false,
        [parameter( HelpMessage="Pass an alternate credential")]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    BEGIN
    {
        if ($PromptForCredential)
        {
            $Credential = Get-Credential
        }
    }
    PROCESS
    {
        $computers = @()
        $computers += $ComputerName
        
        Foreach ($computer in $computers)
        {
            $wmiparams = @{ 
                           Class = 'Win32_DiskDrive'
                           ComputerName = $computer
                           ErrorAction = 'Stop'
                          } 
            $wmiquery = @{ 
                          ComputerName = $computer
                         }
            if ($Credential -ne $null)
            {
                $wmiparams.Credential = $Credential
                $wmiquery.Credential = $Credential
            }
            try
            {
                $diskdrives = @(Get-WmiObject @wmiparams)
                $WMIErrors = $false
            }
            catch
            {
                Write-Warning "Error: There was an issue retrieving disk information from $computer"
                $WMIErrors = $true
            }
            
            if (!$WMIErrors)
            {
                # There are no direct relationships between win32_volume and win32_diskdrive so I have 
                #  to process seperately to try to find mount points. How ugly and stupid....
                $wmiparams.Class = 'Win32_Volume'
                $mountpoints = @(Get-WmiObject @wmiparams | where {$_.DriveLetter -eq $null})
                
                # Get most of our standard disk information
                foreach ($diskdrive in $diskdrives) 
                {
                    $wmiquery.Query = "ASSOCIATORS OF {Win32_DiskDrive.DeviceID=`"$($diskdrive.DeviceID.replace('\','\\'))`"} WHERE AssocClass = Win32_DiskDriveToDiskPartition"
                    $partitions = @(Get-WmiObject @wmiquery)
                    foreach ($partition in $partitions)
                    {
                        $objprops = @{
                                       Computer = $computer
                                       Disk = $diskdrive.Name
                                       Model = $diskdrive.Model
                                       Partition = $partition.Name
                                       Description = $partition.Description
                                       PrimaryPartition = $partition.PrimaryPartition
                                       VolumeName = ''
                                       Drive = ''
                                       DiskSize = ''
                                       FreeSpace = ''
                                       PercentageFree = ''
                                       DiskType = 'Disk'
                                       SerialNumber = $diskdrive.SerialNumber
                                     }
                        
                        $wmiquery.Query = "ASSOCIATORS OF {Win32_DiskPartition.DeviceID=`"$($partition.DeviceID)`"} WHERE AssocClass = Win32_LogicalDiskToPartition"
                        $logicaldisks = @(Get-WmiObject @wmiquery)
                        foreach ($logicaldisk in $logicaldisks)
                        {
                            $objprops.Drive = $logicaldisk.Name
                            $objprops.DiskSize = [math]::round($logicaldisk.Size/1GB, 2)
                            $objprops.FreeSpace = [math]::round($logicaldisk.FreeSpace/1GB, 2)
                            $objprops.PercentageFree = [math]::round((($logicaldisk.FreeSpace/$logicaldisk.Size)*100), 2)
                            $objprops.DiskType = 'Partition'
                            $objprops.VolumeName = $logicaldisk.VolumeName
                        }
                        New-Object psobject -Property $objprops
                    }
                }
                foreach ($mountpoint in $mountpoints)
                {
                    $objprops = @{
                                   Computer = $computer
                                   Disk = $mountpoint.Name
                                   Model = ''
                                   Partition = ''
                                   Description = $mountpoint.Caption
                                   PrimaryPartition = ''
                                   VolumeName = ''
                                   Drive = [Regex]::Match($mountpoint.Caption, "^.:\\").Value
                                   DiskSize = [math]::round($mountpoint.Capacity/1Gb, 2)
                                   FreeSpace = [math]::round($mountpoint.FreeSpace/1Gb, 2)
                                   PercentageFree = [math]::round((($mountpoint.FreeSpace/$mountpoint.Capacity)*100), 2)
                                   DiskType = 'MountPoint'
                                   SerialNumber = $mountpoint.SerialNumber
                                 }
                    New-Object psobject -Property $objprops
                }
            }
        }
    }
}