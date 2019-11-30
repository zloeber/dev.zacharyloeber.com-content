Function Get-RemoteRegistry 
{
<#
.SYNOPSIS
   Returns value of a registry key from a remote system from a different domain or workgroup
.DESCRIPTION
   Returns value of a registry key from a remote system from a different domain or workgroup. This also allows
   the use of an alternate credential.
.PARAMETER ComputerName
    Computer to connect to for registry values
.PARAMETER Hive
    Registry Hive (Default is HKLM)
.PARAMETER Key
    Registry Key
.PARAMETER SubKey
    Registry Subkey
.PARAMETER PromptForCredential
    Set this if you want the function to prompt for alternate credentials
.PARAMETER Credential
    Pass an alternate credential
.NOTES
    Name       : Get-RemoteRegistry
    Version    : 1.0.0 June 16th 2013
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

.EXAMPLE
    $Cred = Get-Credential
    Get-RemoteRegistry -ComputerName '192.168.1.100' -Credential $Cred -Key:"SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Subkey NtpServer
    
    Description
    -----------
    Returns the registry subkey for the ntp server in use by the time service
#>
    [CmdletBinding()]
    param(
    	[Parameter( Position=0,
                    ValueFromPipeline=$true,
                    HelpMessage="Computer to connect to for registry values" )]
    	[String[]]$ComputerName = $env:computername,
    	[Parameter( HelpMessage="Registry Hive (Default is HKLM)" )]
    	[UInt32]$Hive = 2147483650,
    	[Parameter( Mandatory=$true,
                    HelpMessage="Registry Key" )]
    	[String]$Key,
    	[Parameter( Mandatory=$true,
                    HelpMessage="Registry Subkey" )]
    	[String]$SubKey,
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
        $_computers = @()
        if ($ComputerName)
        {
            $_computers += $ComputerName
        }
        $wmiparams = @{ 
                        List = $true
                        Namespace = 'root\default'
                        ErrorAction = 'Stop'
                        Class = 'StdRegProv'
                      }
        if ($Credential -ne $null)
        {
            $wmiparams.Credential = $Credential
        }
        Foreach ($computer in $_computers)
        {
            $wmiparams.ComputerName = $computer
            try
            {
                $reg = Get-WmiObject @wmiparams
        		$subkeys = $reg.GetStringValue($Hive, $Key, $Subkey)
        		$subkeys.sValue
            }
            catch
            {
                $date = get-date -Format MM-dd-yyyy
                $time = get-date -Format hh.mm
                $erroroutput = "$date;$time;$ComputerName;Error;$_"
                Write-Warning $erroroutput
            }
        }
	}
}

Function Get-RemoteService
{
<#
.SYNOPSIS
    Retrieve remote service information.
.DESCRIPTION
    Retreives remote service information with WMI and, optionally, a different credentail.
.PARAMETER Name
    The service name to return. Accepted via pipeline.
.PARAMETER ComputerName
    Computer with service to check
.PARAMETER IncludeDriverServices
    Include the normally hidden kernel and file system drivers. Only applicable when calling the function
    without a service name specified.
.PARAMETER PromptForCredential
    Set this if you want the function to prompt for alternate credentials
.PARAMETER Credential
    Pass an alternate credential
.NOTES
    Name       : Get-RemoteService
    Version    : 1.0.0 July 16th 2013
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
    
.EXAMPLE
    $Cred = Get-Credential
    Get-Service | Get-RemoteService -ComputerName 'testserver1' -Credential $Cred | Measure-Object

    Description:
    ------------------
    Returns a count of all services on testserver1 with the same name as those found on the local system
    using alternate credentials.
.EXAMPLE
    Get-RemoteService -ComputerName 'testserver1' -PromptForCredentials $true

    Description:
    ------------------
    Returns all services on testserver1 prompting for credentials (once).
#>
    [CmdletBinding()]
    param( 
        [Parameter( Position=0,
                    ValueFromPipelineByPropertyName=$true,                    
                    ValueFromPipeline=$true,
                    HelpMessage="The service name to return." )]
        [Alias('ServiceName')]
        [string[]]$Name,
        [parameter( HelpMessage="Computer with service to check" )]
        [string]$ComputerName = $env:computername,
        [parameter( HelpMessage="Include the normally hidden driver services. Only applicable when not supplying a specific service name." )]
        [bool]$IncludeDriverServices = $false,
        [parameter( HelpMessage="Set this if you want the function to prompt for alternate credentials" )]
        [bool]$PromptForCredential = $false,
        [parameter( HelpMessage="Pass an alternate credential" )]
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
        $services = @()
        if ($Name)
        {
            $services += $Name
        }
        $wmiparams = @{ 
                        Namespace = 'root\CIMV2'
                        Class = 'Win32_Service'
                        ComputerName = $ComputerName
                        ErrorAction = 'Stop'
                      }
        if ($Credential -ne $null)
        {
            $wmiparams.Credential = $Credential
        }
        if ($services.count -ge 1)
        {
            Foreach ($service in $services)
            {
                $wmiparams.Filter = "Name='$($service)'"
                
                try
                {
                    $wmiparams.Class = 'Win32_Service'
                    $result = Get-WmiObject @wmiparams | select Name,DisplayName,PathName,Started,StartMode,State,ServiceType
                    if ($result -eq $null)
                    {
                        $wmiparams.Class = 'Win32_SystemDriver'
                        $result = Get-WmiObject @wmiparams | select Name,DisplayName,PathName,Started,StartMode,State,ServiceType
                    }
                    if ($result -ne $null)
                    {
                        $result
                    }
                }
                catch
                {
                    $date = get-date -Format MM-dd-yyyy
                    $time = get-date -Format hh.mm
                    $erroroutput = "$date;$time;$ComputerName;$service;$_"
                    Write-Warning $erroroutput
                }
            }
        }
        else
        {
            $wmiparams.Filter = ""
            try
            {
                $result = Get-WmiObject @wmiparams | select Name,DisplayName,PathName,Started,StartMode,State,ServiceType
                if (($result -ne $null) -and ($IncludeDriverServices))
                {
                    $wmiparams.Class = 'Win32_SystemDriver'
                    $result += Get-WmiObject @wmiparams | select Name,DisplayName,PathName,Started,StartMode,State,ServiceType
                }
                if ($result -ne $null)
                {
                    $result
                }
            }
            catch
            {
                $date = get-date -Format MM-dd-yyyy
                $time = get-date -Format hh.mm
                $erroroutput = "$date;$time;$ComputerName;$service;$_"
                Write-Warning $erroroutput
            }
        }
    }
}

Function Get-RemoteServiceDependency
{
<#
.SYNOPSIS
    Retrieve remote (or local) service dependency information.
.DESCRIPTION
    Retreives remote (or local) service dependency information via WMI and, optionally, a different credentail.
.PARAMETER Name
    Service to list dependencies
.PARAMETER ComputerName
    Computer with service to check
.PARAMETER PromptForCredential
    Set this if you want the function to prompt for alternate credentials
.PARAMETER Credential
    Pass an alternate credential

.NOTES
    Name       : Get-RemoteServiceDependency 
    Version    : 1.0.0 June 16th 2013
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
                 
.EXAMPLE
    Get-RemoteServiceDependency -Name 'netlogon' -ComputerName 'testserver1' -PromptForCredential $true| ft

    Description:
    ------------------
    Get service dependency information for the netlogon service for testserver1 after prompting for credentials.

.LINK
    http://zacharyloeber.com/
.LINK
    http://nl.linkedin.com/in/zloeber
#>

    [cmdletBinding()]
    param(
        [parameter( Position=0,
                    Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$true,
                    ValueFromPipeline=$true,
                    HelpMessage="Service to list dependencies")]
        [Alias('ServiceName')]
        [string]$Name,
        [parameter( HelpMessage="Computer with service to check")]
        [string]$ComputerName = $env:computername,
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
        $_ServiceNames = @()
        $_ServiceNames += $Name
        $wmiparameters = @{ 
                            ComputerName = $ComputerName
                            ErrorAction = "Stop"
                          }
        if ($Credential -ne $null)
        {
            $wmiparameters.Credential = $Credential
        }

        Foreach ($_ServiceName in $_ServiceNames)
        {
            $wmiparams = @{ 
                            ComputerName = $ComputerName
                            ErrorAction = 'Stop'
                          }
            $wmiparameters.Query = "Associators of {Win32_Service.Name='$_ServiceName'} Where ResultRole=Antecedent"
            try
            {
                $results = @(Get-WmiObject @wmiparameters | select Name, DisplayName, StartMode, State, ServiceType)
                if ($results -ne $null)
                {
                    Foreach ($result in $results)
                    {
                        $outputproperties = @{
                                                Name = $result.Name;
                                                DisplayName = $result.DisplayName;
                                                StartMode = $result.StartMode;
                                                State = $result.State;
                                                ServiceType = $result.Servicetype
                                             }
                        New-Object psobject -Property $outputproperties
                    }
                }
            }
            catch
            {
                $date = get-date -Format MM-dd-yyyy
                $time = get-date -Format hh.mm
                $erroroutput = "$date;$time;$ComputerName;Error;$_"
                Write-Warning $erroroutput
            }
        }
    }
}

Function Get-RemoteServiceDependencyTree
{
    param( 
        [Parameter( Position=0,
                    Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    HelpMessage="The service name to return dependencies on.")]
        [Alias('ServiceName')]
        [string]$Name,
        [parameter( HelpMessage="Computer to gather dependency tree information from. Defaults to local machine.")]
        [string]$ComputerName = $env:computername,
        [Parameter( HelpMessage="When first calling this function set this to true to indicate the service is the begining of a possible tree of dependencies. This will never be called within the function.")]
        [bool]$IsRootService = $false,
        [parameter( HelpMessage="Set this if you want to include kernal and file system driver dependencies")]
        [bool]$IncludeDriverServices = $true,
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
        $_servicenames = @()
        $_servicenames += $Name
        Foreach ($_service in $_servicenames)
        {
            $serviceparam = @{
                              Name = $_service
                              ComputerName = $ComputerName
                             }
            if ($Credential -ne $null)
            {
                $serviceparam.Credential = $Credential
            }

            # Get the service and its depenendy information
            $curservice = Get-RemoteService @serviceparam
            if ($IncludeDriverServices)
            {
                $curservicedependencies = @(Get-RemoteServiceDependency @serviceparam)
            }
            else
            {
                $curservicedependencies = @(Get-RemoteServiceDependency @serviceparam | Where {$_.ServiceType -notlike "*Driver"})
            }
            $results = @()

            # if there are dependencies for the current service
            if ($curservicedependencies -ne $null)
            {
                foreach ($curservicedependency in $curservicedependencies) 
                {
                    $resultproperty = @{ 
                                         ID = $curservice.name+$curservicedependency.name;
                                         Service = $curservice.name;
                                         ServiceStatus = $curservice.state;
                                         ServiceType = $curservice.servicetype;
                                         Dependency = $curservicedependency.name;
                                         DependencyStatus = $curservicedependency.state;
                                         DependencyServiceType = $curservicedependency.servicetype;
                                       }
                    $resultobj = New-Object PsObject -Property $resultproperty
                    $results += $resultobj

                    # change the service name parameter to the dependency service name then recurse for results
                    $serviceparam.name = $curservicedependency.Name
                    $serviceparam.IncludeDriverServices = $IncludeDriverServices
                    $tempresults = @(Get-RemoteServiceDependencyTree @serviceparam)
                    if ($tempresults -ne $null)
                    {
                        $results += $tempresults
                    }
                }
            }
            else    # if no dependencies exist for the current service
            {
                # If this service is a root service return it as dependant upon itself
                if ($IsRootService) 
                {
                    $resultproperty = @{ 
                                         ID = $curservice.name+$curservice.name;
                                         Service = $curservice.name;
                                         ServiceStatus = $curservice.state;
                                         ServiceType = $curservice.servicetype;
                                         Dependency = $curservice.name;
                                         DependencyStatus = $curservice.state;
                                         DependencyServiceType = $curservice.servicetype;
                                       }
                    $resultobj = New-Object PsObject -Property $resultproperty
                    $results += $resultobj
                }
            }
            if ($results -ne $null)
            {
                $results
            }
        }
    }
}

#####
# Modify the next command to suit your needs (always call with IsRootService set to $true)
#####

# Example 1: Get the netlogon service locally  
$servicetree = @(Get-RemoteServiceDependencyTree -Name 'netlogon' -IsRootService $true) 

# Example 2: Get the netlogon service on the remote 'server1' prompting for credentials before connecting
#$servicetree = @(Get-RemoteServiceDependencyTree -Name 'netlogon' -IsRootService $true -ComputerName 'server1' -PromptForCredential)

# Example 3: Get any service with "Exchange" in the name on a remote server called 'server1'
#$Cred = Get-Credential
#$servicetree = @(get-remoteservice -IncludeDriverServices $true -Credential $Cred -ComputerName 'server1' | where {$_.Name -like "*exchange*"} | Get-RemoteServiceDependencyTree -IsRootService $true -Credential $Cred -ComputerName 'server1')

# This removes possible duplicate node connections
$servicetree = $servicetree | Sort-Object ID -Unique

# Use the following to determine our map node properties (this feels like a hack, maybe there is a better
# way to do this?)
$allservices = @()
$servicetree | ForEach-Object -Process {
    $allServices += New-Object psobject -Property @{Name = $_.Service; Status = $_.ServiceStatus; ServiceType = $_.ServiceType}
    $allServices += New-Object psobject -Property @{Name = $_.Dependency; Status = $_.DependencyStatus; ServiceType = $_.DependencyServiceType}
}
$allservices = $allservices | Sort-Object Name -Unique

#region Generate the graphviz diagram data
$Output = @'
digraph test {
 rankdir = LR
 
'@

# Add in the color fill information
ForEach ($service in $allservices) 
{
    switch ($service.Status) {
    	"Stopped" {
            $fillcolor = 'red'
    	}
    	"Running" {
    		$fillcolor = 'green'
    	}
    	default {
    		$fillecolor = 'yellow'
    	}
    }
    if ($service.servicetype -like "*Driver")
    {
            $linetype = 'dashed'
    }
    else
    {
            $linetype = 'solid'
    }

    $Output += @"
    
 "$($service.Name)" [style="filled,$($linetype)",fillcolor=$($fillcolor)]
"@`
 }

# Add in the dependency information
ForEach ($service in $servicetree) {
    $Output += @"    
    
 "$($service.Service)" -> "$($service.Dependency)"[label = "Depends On"]
"@
}

$Output += @'

}
'@

# Uncomment the following to create a file to later convert into a graph with dot.exe
#$Output | Out-File -Encoding ASCII '.\testout1.txt'

# Otherwise feed it into dot.exe and automatically open it up
$Output | & 'dot.exe' -Tpng -o services.png
ii services.png
#endregion Generate the graphviz diagram data