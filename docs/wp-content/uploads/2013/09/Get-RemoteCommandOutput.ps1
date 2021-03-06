Function New-RemoteCommand
{
    <#
    .SYNOPSIS
        Uses WMI to send a command to a remote system and store the results in a local file. 
    .DESCRIPTION
        Uses WMI and file copying trickery to get the results of a remotely executed command.
    .PARAMETER ComputerName
        Specifies the target computer for data query.
    .PARAMETER cmdTimeOutValue
        Time, in seconds, in which we should wait for the remote command process ID to complete. Default
        is 10 seconds.
    .PARAMETER cmdResultsLocation
        Location on the remote system to store the results of the command. Default is the env:systemroot\TEMP
        directory (usually C:\Windows\TEMP)
    .PARAMETER $cmdUniqueID
        A unique identifier to use for the remote results file name to utilize in its name. By default it is the
        current time in UTC converted to ticks. You can modify this if you always want the same name to be used.
        (Note: The remote results file name is in the format of <ComputerName>_<UniqueID>.tmp
    .PARAMETER ThrottleLimit
        Specifies the maximum number of systems to inventory simultaneously 
    .PARAMETER Timeout
        Specifies the maximum time in second command can run in background before terminating this thread.
    .PARAMETER ShowProgress
        Show progress bar information
    .EXAMPLE
       PS > New-RemoteCommand

       <output>
       
       Description
       -----------
       <Placeholder>

    .NOTES
       Author: Zachary Loeber
       Site: http://zacharyloeber.com/
       Requires: Powershell 2.0

       Version History
       1.0.0 - 08/31/2013
        - Initial release
    #>
    [CmdletBinding()]
    PARAM
    (
        [Parameter(HelpMessage="Computer or computers to gather information from",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias('DNSHostName','PSComputerName')]
        [string[]]
        $ComputerName=$env:computername,
       
        [Parameter(HelpMessage='Command to execute on remote system')]
        [string]
        $RemoteCMD,
        
        [Parameter(HelpMessage='Time to wait for remote command to complete (in seconds) before giving up.')]
        [int]
        $cmdTimeOutValue = 10,
        
        [Parameter(HelpMessage='Alternate location to copy command result files on the remote host. Default is to the %systemroot%\temp directory')]
        [string]
        $cmdResultsLocation,
        
        [Parameter(HelpMessage='Command unique identifier. Defaults to random(ish) string')]
        [string]
        $cmdUniqueID = (Get-Date).touniversaltime().ticks,
        
        [Parameter(HelpMessage="Maximum number of concurrent threads")]
        [ValidateRange(1,65535)]
        [int32]
        $ThrottleLimit = 32,
 
        [Parameter(HelpMessage="Timeout before a thread stops trying to gather the information")]
        [ValidateRange(1,65535)]
        [int32]
        $Timeout = 120,
 
        [Parameter(HelpMessage="Display progress of function")]
        [switch]
        $ShowProgress,
        
        [Parameter(HelpMessage="Set this if you want the function to prompt for alternate credentials")]
        [switch]
        $PromptForCredential,
        
        [Parameter(HelpMessage="Set this if you want to provide your own alternate credentials")]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    BEGIN
    {
        # Gather possible local host names and IPs to prevent credential utilization in some cases
        Write-Verbose -Message 'Remote Command Execution: Creating local hostname list'
        $IPAddresses = [net.dns]::GetHostAddresses($env:COMPUTERNAME) | Select-Object -ExpandProperty IpAddressToString
        $HostNames = $IPAddresses | ForEach-Object {
            try {
                [net.dns]::GetHostByAddress($_)
            } catch {
                # We do not care about errors here...
            }
        } | Select-Object -ExpandProperty HostName -Unique
        $LocalHost = @('', '.', 'localhost', $env:COMPUTERNAME, '::1', '127.0.0.1') + $IPAddresses + $HostNames
 
        Write-Verbose -Message 'Remote Command Execution: Creating initial variables'
        $runspacetimers       = [HashTable]::Synchronized(@{})
        $runspaces            = New-Object -TypeName System.Collections.ArrayList
        $bgRunspaceCounter    = 0
        
        if ($PromptForCredential)
        {
            $Credential = Get-Credential
        }
        
        Write-Verbose -Message 'Remote Command Execution: Creating Initial Session State'
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        foreach ($ExternalVariable in ('runspacetimers', 'Credential', 'LocalHost'))
        {
            Write-Verbose -Message "Remote Command Execution: Adding variable $ExternalVariable to initial session state"
            $iss.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $ExternalVariable, (Get-Variable -Name $ExternalVariable -ValueOnly), ''))
        }
        
        Write-Verbose -Message 'Remote Command Execution: Creating runspace pool'
        $rp = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $iss, $Host)
        $rp.ApartmentState = 'STA'
        $rp.Open()
 
        # This is the actual code called for each computer
        Write-Verbose -Message 'Remote Command Execution: Defining background runspaces scriptblock'
        $ScriptBlock = {
            [CmdletBinding()]
            Param
            (
                [Parameter(Position=0)]
                [string]
                $ComputerName,
 
                [Parameter(Position=1)]
                [int]
                $bgRunspaceID,
                
                [Parameter()]
                [string]
                $RemoteCMD,
                
                [Parameter()]
                [int]
                $cmdTimeOutValue,
                
                [Parameter()]
                [string]
                $cmdResultsLocation,
                
                [Parameter()]
                [string]
                $cmdUniqueID
            )
            $runspacetimers.$bgRunspaceID = Get-Date
            
            try
            {
                Write-Verbose -Message ('Remote Command Execution: Runspace {0}: Start' -f $ComputerName)
                $WMIHast = @{
                    ComputerName = $ComputerName
                    ErrorAction = 'Stop'
                }
                
                $BitsCred = @{
                    ErrorAction = 'Stop'                    
                }
                if (($LocalHost -notcontains $ComputerName) -and ($Credential -ne $null))
                {
                    $WMIHast.Credential = $Credential
                    $wshcred_user =  $Credential.GetNetworkCredential().UserName
                    $wshcred_pwd = $Credential.GetNetworkCredential().Password
                }

                # General variables
                $PSDateTime = Get-Date
                
                #region Remote Command
                Write-Verbose -Message ('Remote Command Execution: Runspace {0}: information' -f $ComputerName)

                # Modify this variable to change your default set of display properties
                $defaultProperties    = @('ComputerName','RemoteOutputFullSharePath','CommandResults')

                # Get the system root information to store our temp file
                if (($cmdResultsLocation -eq $null) -or ($cmdResultsLocation -eq ''))
                {
                    $reg_ExtendedInfo = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion'
                    $wmi_registry = Get-WmiObject @WMIHast -Class StdRegProv -Namespace 'root\default' -List:$true
                    $RemoteSystemRoot = ($wmi_registry.GetStringValue('2147483650',$reg_ExtendedInfo,'SystemRoot')).sValue
                    $cmdResultsLocalPath = "$($RemoteSystemRoot)\TEMP"
                }
                else
                {
                    $cmdResultsLocalPath = $cmdResultsLocation
                }
                
                $cmdResultsFileName  = "$($ComputerName)_$($cmdUniqueID).tmp"
                $cmdResultsLocalFullPath = "$($cmdResultsLocalPath)\$($cmdResultsFileName)"
                $cmdResultsSharePath = "\\$($ComputerName)\$($cmdResultsLocalPath -replace ':','$')"
                $cmdResultsFullSharePath = "$($cmdResultsSharePath)\$($cmdResultsFileName)"
                Write-Verbose -Message ('Remote Command Execution: Runspace {0}: Remote Path - {1}' -f $ComputerName,$cmdResultsLocalPath)
                Write-Verbose -Message ('Remote Command Execution: Runspace {0}: Temp File - {1}' -f $ComputerName,$cmdResultsFileName)
                $CMD = "$($RemoteCMD) > $cmdResultsLocalFullPath"
                
                Write-Verbose -Message ('Remote Command Execution: Runspace {0}: Command - {1}' -f $ComputerName,$CMD)
                
                # Kick off the remote command and grab the process id
                $processId = (Invoke-WmiMethod @WMIHast `
                                               -Class Win32_Process `
                                               -Name create `
                                               -ArgumentList $CMD).ProcessId
                                            
                $runningCheck = {Get-WmiObject @WMIHast -Class Win32_Process -Filter "ProcessId='$processId'"}

                $SecondsRun = 0
                $TimedOut = $false
                while (((& $runningCheck) -ne $null) -and (!$TimedOut))
                {
                    Start-Sleep -Seconds 1
                    $SecondsRun = $SecondsRun + 1
                    if ($SecondsRun -eq $CommandTimeLimit)
                    {
                        $TimedOut = $true
                    }
                }
                
                if ($TimedOut)
                {
                    Write-Error ('Remote Command Execution: Runspace {0}: WARNING - Command started but took too long to complete ProcessID {1} ' -f $ComputerName,$ProcessID)
                }
                else
                {
                    $ResultProperty = @{
                        'PSComputerName' = $ComputerName
                        'PSDateTime' = $PSDateTime
                        'ComputerName' = $ComputerName
                        'RemoteOutputFileName' = $cmdResultsFileName
                        'RemoteOutputLocalPath' = $cmdResultsLocalFullPath
                        'RemoteOutputSharePath' = $cmdResultsSharePath
                        'RemoteOutputFullLocalPath' = $cmdResultsLocalFullPath
                        'RemoteOutputFullSharePath' = $cmdResultsFullSharePath
                    }
                    $ResultObject += New-Object -TypeName PSObject -Property $ResultProperty
                }                
                # Setup the default properties for output
                $ResultObject.PSObject.TypeNames.Insert(0,'My.RemoteCMD.Info')
                $defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet',[string[]]$defaultProperties)
                $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)
                $ResultObject | Add-Member MemberSet PSStandardMembers $PSStandardMembers

                Write-Output -InputObject $ResultObject
                #endregion
            }
            catch
            {
                Write-Warning -Message ('Remote Command Execution: {0}: {1}' -f $ComputerName, $_.Exception.Message)
            }
            Write-Verbose -Message ('Remote Command Execution: Runspace {0}: End' -f $ComputerName)
        }
 
        Function Get-Result
        {
            [CmdletBinding()]
            Param 
            (
                [switch]$Wait
            )
            do
            {
                $More = $false
                foreach ($runspace in $runspaces)
                {
                    $StartTime = $runspacetimers.($runspace.ID)
                    if ($runspace.Handle.isCompleted)
                    {
                        Write-Verbose -Message ('Remote Command Execution: Thread done for {0}' -f $runspace.IObject)
                        $runspace.PowerShell.EndInvoke($runspace.Handle)
                        $runspace.PowerShell.Dispose()
                        $runspace.PowerShell = $null
                        $runspace.Handle = $null
                    }
                    elseif ($runspace.Handle -ne $null)
                    {
                        $More = $true
                    }
                    if ($Timeout -and $StartTime)
                    {
                        if ((New-TimeSpan -Start $StartTime).TotalSeconds -ge $Timeout -and $runspace.PowerShell)
                        {
                            Write-Warning -Message ('Timeout {0}' -f $runspace.IObject)
                            $runspace.PowerShell.Dispose()
                            $runspace.PowerShell = $null
                            $runspace.Handle = $null
                        }
                    }
                }
                if ($More -and $PSBoundParameters['Wait'])
                {
                    Start-Sleep -Milliseconds 100
                }
                foreach ($threat in $runspaces.Clone())
                {
                    if ( -not $threat.handle)
                    {
                        Write-Verbose -Message ('Remote Command Execution: Removing {0} from runspaces' -f $threat.IObject)
                        $runspaces.Remove($threat)
                    }
                }
                if ($ShowProgress)
                {
                    $ProgressSplatting = @{
                        Activity = 'Remote Command Execution: Getting info'
                        Status = 'Remote Command Execution: {0} of {1} total threads done' -f ($bgRunspaceCounter - $runspaces.Count), $bgRunspaceCounter
                        PercentComplete = ($bgRunspaceCounter - $runspaces.Count) / $bgRunspaceCounter * 100
                    }
                    Write-Progress @ProgressSplatting
                }
            }
            while ($More -and $PSBoundParameters['Wait'])
        }
    }
    PROCESS
    {
        foreach ($Computer in $ComputerName)
        {
            $bgRunspaceCounter++
            $psCMD = [System.Management.Automation.PowerShell]::Create().AddScript($ScriptBlock)
            $null = $psCMD.AddParameter('bgRunspaceID',$bgRunspaceCounter)
            $null = $psCMD.AddParameter('ComputerName',$Computer)
            $null = $psCMD.AddParameter('RemoteCMD',$RemoteCMD)
            $null = $psCMD.AddParameter('cmdTimeOutValue',$cmdTimeOutValue)
            $null = $psCMD.AddParameter('cmdUniqueID',$cmdUniqueID)
            $null = $psCMD.AddParameter('cmdResultsLocation',$cmdResultsLocation)
            $null = $psCMD.AddParameter('Verbose',$VerbosePreference)
            $psCMD.RunspacePool = $rp
 
            Write-Verbose -Message ('Remote Command Execution: Starting {0}' -f $Computer)
            [void]$runspaces.Add(@{
                Handle = $psCMD.BeginInvoke()
                PowerShell = $psCMD
                IObject = $Computer
                ID = $bgRunspaceCounter
           })
           Get-Result
        }
    }
    END
    {
        Get-Result -Wait
        if ($ShowProgress)
        {
            Write-Progress -Activity 'Remote Command Execution: Sending command' -Status 'Done' -Completed
        }
        Write-Verbose -Message "Remote Command Execution: Closing runspace pool"
        $rp.Close()
        $rp.Dispose()

    }
}

Function Get-RemoteCommandResults
{
    <#
    .SYNOPSIS
        Uses WMI to send a command to a remote system and store the results in a local file. 
    .DESCRIPTION
        Uses WMI and file copying trickery to get the results of a remotely executed command.
    .PARAMETER InputObject
        Object or array of objects returned from New-RemoteCommand
    .PARAMETER LeaveRemoteFile
        By default the remote file containing the commadn output is removed. Use this switch to leave it alone.
    .PARAMETER Credential
        Set this if you want to provide your own alternate credentials.
    .EXAMPLE
       PS > $a = Get-RemoteCommandResults $cmdresults
       
       Description
       -----------
       Gather and store the results of the remotely run command output generated from New-RemoteCommand

    .NOTES
       Author: Zachary Loeber
       Site: http://zacharyloeber.com/
       Requires: Powershell 2.0

       Version History
       1.0.0 - 09/19/2013
        - Initial release
    
    ** This is a supplement function to New-RemoteCommand **
    #>
    [CmdletBinding()]
    PARAM
    (
        [Parameter(HelpMessage='Object or array of objects returned from New-RemoteCommand')]
        $InputObject,
        
        [Parameter(HelpMessage='By default the remote file containing the commadn output is removed. Use this switch to leave it alone.')]
        [switch]
        $LeaveRemoteFile,
        
        [Parameter(HelpMessage="Set this if you want to provide your own alternate credentials")]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )
    BEGIN
    {
        if ($Credential -ne $null)
        {
            $wshcred_user= $Cred.GetNetworkCredential().UserName
            $wshcred_pwd = $Cred.GetNetworkCredential().Password
        }
        $netobj = New-Object -com WScript.Network
        $results = @()
    }
    PROCESS
    {
        $results += $InputObject
    }
    END
    {
        Foreach ($result in $results)
        {
            $SecChannel = "\\$($result.ComputerName)\IPC`$"
            Write-Verbose -Message ('Remote Command Results {0}: Starting secure channel - {1}' -f $ComputerName,$SecChannel)
            if ($Cred -ne $null)
            {
                $netobj.mapnetworkdrive("", $SecChannel, "false", $wshcred_user, $wshcred_pwd)
            }
            else
            {
                $netobj.mapnetworkdrive("", $SecChannel, "false")
            }
            $cmdResultArray = Get-Content $result.RemoteOutputFullSharePath
            if (!$LeaveRemoteFile)
            {
                Remove-Item $result.RemoteOutputFullSharePath
            }
            $result | Add-Member -MemberType NoteProperty -Name 'CommandResults' -Value $cmdResultArray            
            $netobj.RemoveNetworkDrive($SecChannel)
        }
        $InputObject
    }
}

Function Get-VSSInfoFromRemoteCommandResults
{
    <#
    .SYNOPSIS
        Converts the results of vssadmin list writer into powershell friendly objects.
    .DESCRIPTION
        Converts the results of vssadmin list writer into powershell friendly objects.
    .PARAMETER InputObject
        Object or array of objects returned from Get-RemoteCommandResults
    .EXAMPLE
        PS > $a = Get-RemoteCommandResults $cmdresults

        Description
        -----------
        Gather and store the results of the remotely run command output generated from New-RemoteCommand

    .NOTES
        Author: Zachary Loeber
        Site: http://zacharyloeber.com/
        Requires: Powershell 2.0

        Version History
        1.0.0 - 09/19/2013
        - Initial release
    
        ** This is a supplement function to New-RemoteCommand and Get-RemoteCommandResults **
    #>
    [CmdletBinding()]
    PARAM
    (
        [Parameter(HelpMessage='Object or array of objects returned from Get-RemoteCommandResults')]
        $InputObject
    )
    BEGIN
    {
        $VSSResults = @()
        $Results = @()
    }
    PROCESS
    {
        $Results += $InputObject
    }
    END
    {
        Foreach ($result in $Results)
        {
            $VSSWriters = @()
            $output = $result.CommandResults
            for ($i=0; $i -lt $output.Count; $i++)
            {        if ($output[$i] -match 'Writer name')
                {
                    $vssprops = @{
                        'WriterName' = [regex]::match($output[$i],'(?<=:)(.+)').value
                        'WriterID' = [regex]::match($output[$i+1],'(?<=:)(.+)').value
                        'WriterInstanceID' = [regex]::match($output[$i+2],'(?<=:)(.+)').value
                        'State' = [regex]::match($output[$i+3],'(?<=:)(.+)').value
                        'LastError' = [regex]::match($output[$i+4],'(?<=:)(.+)').value
                    }
                    $VSSWriters += New-Object PSObject -Property $vssprops
                    $i = ($i + 4)
                }
            }
            $VSSResultProps = @{
                'PSComputerName' = $result.PSComputerName
                'PSDateTime' = $result.PSDateTime
                'ComputerName' = $result.ComputerName
                'VSSWriters' = $VSSWriters
            }
            $VSSResults += New-Object PSObject -Property $VSSResultProps
        }
        $VSSResults
    }
}

$Comptuers = @('Server1','Server2')
$Cred = Get-Credential
$Command = "cmd.exe /C vssadmin list writers"
$runcmd = @(New-RemoteCommand -ComputerName $Computers `
                              -Credential $Cred `
                              -RemoteCMD $command `
                              -Verbose)
$results = Get-RemoteCommandResults -InputObject $runcmd -Verbose
$VSSResults = Get-VSSInfoFromRemoteCommandResults -InputObject $results
$VSSResults.VSSWriters | 
    Select @{n='Computer';e={$VSSResults.ComputerName}},WriterName,State,LastError