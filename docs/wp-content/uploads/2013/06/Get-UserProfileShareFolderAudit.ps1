Function Get-UserProfileShareFolderAudit
{
    <#
    .Synopsis
        Perform a general audit of a user profile directory on a file server  
    .DESCRIPTION
        If you find yourself needing to go through a load of old user profiles this function may
        be able to help. This function goes through a specified directory and can perform the following:
            - Look up user ids in AD which match the folder names and determine if they are enabled or even exist.
            - Move profiles where users are disabled to another folder
            - Move profiles where users are not found to another folder
            - Report on the size of each profile folder
            - Report on the most recently updated file within each profile folder
            - Report if errors were found accessing any files within a profile folder
    .PARAMETER HomeFolderPath
        The local folder with user profiles to audit.
    .PARAMETER MoveToFolderAccountMissing
        If the AD user lookup cannot find an account then move the profile folder to this directory (requires UserStatus).
    .PARAMETER MoveToFolderAccountDisabled
        If the AD user lookup finds a disabled account then move the profile folder to this directory (requires UserStatus).
    .PARAMETER UserStatus
        Check AD for a user ID matching the folder name then report if it is disabled, enabled, or not found.
    .PARAMETER ExtraADUserProperties
        Include additional AD user properties.
    .PARAMETER FolderSize
        Report on each folder total size.
    .PARAMETER LastModified
        Report on the last modified file date in each folder.
    .PARAMETER CheckErrors
        Check all items beneath the profile folders and report on any errors encountered.
    .LINK
        http://zacharyloeber.com
    .LINK
        http://nl.linkedin.com/in/zloeber
    .NOTES
        Any of the folder move options are meant to target the local volume.    
    Name            :   Get-UserProfileShareFolderAudit
    Last edit       :   June 21th 2013
    Version         :   1.0.0 June 21th 2013        
                         - First release
    Author          :   Zachary Loeber
    Disclaimer      :   
        This script is provided AS IS without warranty of any kind. I disclaim all implied warranties including, without limitation,
        any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or
        performance of the sample scripts and documentation remains with you. In no event shall I be liable for any damages whatsoever
        (including, without limitation, damages for loss of business profits, business interruption, loss of business information,
        or other pecuniary loss) arising out of the use of or inability to use the script or documentation. 
    To improve      :   Possibly inclue options to move the folders to different drives.
    Copyright       :   I believe in sharing knowledge, so this script and its use is subject to : http://creativecommons.org/licenses/by-sa/3.0/

    .EXAMPLE
        Get-UserProfileShareFolderAudit -HomeFolderPath c:\scripts\
        
        Description
        -----------
        Returns a report of all folders beneath c:\scripts with the following information:
            - Whether the folders match up to AD accounts, 
            - If an AD account is found, additional AD properties will be displayed for the account
            - The size of the folder
            - The most recent update date/time item in the folder
            - If there are any errors reported in processing the folder.
    #>
    [CmdletBinding()]
    param( 
        [Parameter( Position=0,
                    Mandatory=$true,
                    ValueFromPipeline=$true,
                    HelpMessage="Directory where file shares reside.")]
        [String]$HomeFolderPath, 
        [Parameter( HelpMessage="Directory to move folders with no associated account name in AD.")]
        [String]$MoveToFolderAccountMissing,
    	[Parameter( HelpMessage="Directory to move folders associated with disabled accounts.")]
        [String]$MoveToFolderAccountDisabled,
    	[Parameter( HelpMessage="Check AD for username equal to that of the folder name.")]
        [bool]$UserStatus = $true,
        [Parameter( HelpMessage="Include additional AD user properties.")]
        [bool]$ExtraADUserProperties = $true,
    	[Parameter( HelpMessage="Include the size of each directory.")]
        [bool]$FolderSize = $true,
    	[Parameter( HelpMessage="Dig into each directory for the most recently modified file.")]
        [bool]$LastModified = $true,
    	[Parameter( HelpMessage="Add errors when accessing folders to output.")]
        [bool]$CheckErrors = $true
    )
    PROCESS {
        $noerrors = $true
        # Check if HomeFolderPath is found, exit with warning message if path is incorrect
        if (!(Test-Path -Path $HomeFolderPath)) 
        {
            Write-Warning "HomeFolderPath not found: $HomeFolderPath"
            $noerrors = $false
        }
        if ($MoveToFolderAccountMissing) 
        {
            if (!(Test-Path -Path $MoveToFolderAccountMissing)) 
            {
                Write-Warning "MoveFolderPath not found: $MoveToFolderAccountMissing" 
                $noerrors = $false
            }
        }
        if ($MoveToFolderAccountDisabled) 
        {
            if (!(Test-Path -Path $MoveToFolderAccountDisabled)) 
            {
                Write-Warning "MoveFolderPath not found: $MoveToFolderAccountDisabled"
                $noerrors = $false
            }
        }
        if ($noerrors) 
        {
            # Main loop, for each folder found under home folder path AD is queried to find a matching samaccountname 
            $ProfileFolders = @(Get-ChildItem -Path "$HomeFolderPath" | Where-Object {$_.PSIsContainer})
            ForEach ($ProfileFolder in $ProfileFolders) 
            {     
                $HashProps = @{
                    'FullPath' = $ProfileFolder.FullName 
                }
                if (($MoveToFolderAccountMissing -ne '') -or ($MoveToFolderAccountDisabled  -ne ''))
                {
                    $HashProps.DestinationFullPath = ''
                }
                
                $CurrentPath = Split-Path $ProfileFolder -Leaf 
                
                # If we are checking for errors in the folders (usually indication of permissions issues, 
                # such as manually set or incorrect ownership)
                if ($CheckErrors) 
                {
                    $Error.clear()
                    $null = Get-ChildItem $ProfileFolder.Fullname -Recurse –Force –ErrorAction SilentlyContinue
                    if (!$?) 
                    {
                        $HashProps.FileErrors = 'An error occurred accessing one or all elements within the folder'
                    }
                    else 
                    {
                        $HashProps.FileErrors = ''
                    }
                }
                
                # If gathering the folder size
                if ($FolderSize) 
                { 
                    $HashProps.SizeinBytes = [long](Get-ChildItem $ProfileFolder.Fullname -Recurse -Force -ErrorAction SilentlyContinue | 
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue | Select-Object -Exp Sum)
                    $HashProps.SizeinMegaBytes = "{0:n2}" -f  ($HashProps.SizeinBytes/1MB) 
                }
                
                # If gathering the last modified date within each folder
                if ($LastModified) 
                {
                    $HashProps.FolderContentLastModified = (Get-ChildItem $ProfileFolder.Fullname -Recurse -Force -ErrorAction SilentlyContinue | 
                        Sort LastWriteTime | select -Last 1).LastWriteTime
                } 

                # If we are doing user AD lookups
                if ($UserStatus) 
                {
                    # Make certain AD lookups are working first
                    try {
                        $ADResult = ([adsisearcher]"(samaccountname=$CurrentPath)").Findone()
                        $HashProps.ADErrors = ''
                    }
                    catch {
                        $HashProps.ADErrors = 'Issue with AD lookup!'
                        Write-Warning "Issue with AD lookup, Set the UserStatus option to false to use this function."
                        exit
                    }

                    # If no matching samaccountname is found in the successful lookup
                    if (!($ADResult))
                    { 
                        $HashProps.UserStatus = 'Does not exist in AD!'
                        if ($ExtraADUserProperties) {
                            $HashProps.UserLastLogon = ''
                            $HashProps.UserFirstName = ''
                            $HashProps.UserLastName = ''
                            $HashProps.UserCN = ''
                            $HashProps.UserADPath = ''
                            $HashProps.UserProfile = ''
                            $HashProps.UserLocked = ''
                            $HashProps.UserADPath = ''
                            $HashProps.UserDisabled = ''
                        }
                        # If we are moving folders which do not match up to user IDs in AD
                        if ($MoveToFolderAccountMissing)
                        { 
                            $HashProps.DestinationFullPath = Join-Path -Path $MoveToFolderAccountMissing -ChildPath (Split-Path $ProfileFolder.FullName -Leaf) 
                            Move-Item -Path $HashProps.FullPath -Destination $HashProps.DestinationFullPath -Force 
                            #&".\roboPowerCopy.ps1 $HashProps.FullPath $HashProps.DestinationFullPath /COPYALL"
                        } 
                	}
                    else 
                    {
                        if ($ExtraADUserProperties) 
                        {
                            $HashProps.UserLastLogon = [datetime]::FromFileTime("$($ADResult.Properties.lastlogontimestamp)")
                            $HashProps.UserFirstName = $ADResult.Properties.givenname[0]
                            $HashProps.UserLastName = $ADResult.Properties.sn[0]
                            $HashProps.UserDisplayName = $ADResult.Properties.displayname[0]
                            $HashProps.UserCN = $ADResult.Properties.cn[0]
                            $HashProps.UserProfile = $ADResult.Properties.profilepath[0]
                            $HashProps.UserADPath = $ADResult.Properties.adspath[0]
                            $HashProps.UserLocked = $false
                            if ($ADResult.Properties.lockouttime -gt 0)
                            {
                                $HashProps.UserLocked = $true
                            }
                            $HashProps.UserDisabled = $false
                            if ([bool]($ADResult.Properties.useraccountcontrol[0] -band 2)) 
                            {
                                $HashProps.UserDisabled = $true
                            }
                        }
                        
                        # If samaccountname is found but the account is disabled
                    	if (([boolean]($ADResult.Properties.useraccountcontrol[0] -band 2))) 
                        { 
                            $HashProps.UserStatus =  'Account is disabled and has a home folder' 
                            if ($MoveToFolderAccountDisabled) 
                            { 
                                $HashProps.DestinationFullPath = Join-Path -Path $MoveToFolderAccountDisabled -ChildPath (Split-Path $ProfileFolder.FullName -Leaf) 
                                Move-Item -Path $HashProps.FullPath -Destination $HashProps.DestinationFullPath -Force 
                                #&".\roboPowerCopy.ps1 $HashProps.FullPath $HashProps.DestinationFullPath /COPYALL"
                            } 
                        }
                        else 
                        {
                            $HashProps.UserStatus =  'Active account found for this profile'
                            if ($MoveToFolderAccountDisabled -or $MoveToFolderAccountMissing) 
                            {
                                $HashProps.DestinationFullPath = 'Not Moved'
                            }
                        }
                    }
                }
                # Output the object 
                New-Object -TypeName PSCustomObject -Property $HashProps 
            }
        }
    }
}