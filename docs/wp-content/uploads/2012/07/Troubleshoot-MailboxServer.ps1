##############################################################################
# NAME: Troubleshoot-MailboxServer.ps1
#
# AUTHOR:	Zachary Loeber
# DATE:	07/18/2012
# EMAIL:	zloeber@gmail.com
#
# COMMENT:  This script is meant for locally automating the following
#			troubleshooting scripts found in %ExchangeInstallPath%Scripts\ and
#			optionally emailing a warning/error color coded report upon completion:
#				Database LatencyTroubleshoot-CI.ps1
#				Troubleshoot-DatabaseLatency.ps1
#				Troubleshoot-DatabaseSpace.ps1
#
#			This script will also (optionally) redistribute your DAG(s) with:
#				RedistributeActiveDatabases.ps1
#			
#			You can schedule this easily like so:
#				cd $exscripts
#				ManageScheduledTask.ps1 -Install –ServerName <Your Server> 
#				 -PsScriptPath C:\Scripts\Troubleshoot-MailboxServer.ps1
#				 –TaskName "Troubleshoot Exchange 2010 Mailbox Servers"
#			(Note: this adds the scheduled task as a generic task, you will still 
#			 need to go into scheduled tasks and set a schedule for it to run 
#		     and add any details to the description)
#
# VERSION HISTORY
# 1.3 - 07/20/2012
#		- Fixed issue preventing script from running on a single server environment
# 1.2 - 07/19/2012
#		- Rolled in optional system report script from 
#          http://www.simple-talk.com/sysadmin/powershell/building-a-daily-systems-report-email-with-powershell/
#		   Requires MS Chart Controls for .Net 3.5
#		    (http://www.microsoft.com/download/en/details.aspx?id=14422)
# 1.1 - 07/18/2012
#		- Added testing mode
#		- Added quarantine option
#		- Added more comments and links
# 1.0 - 07/17/2012 Initial Version.
# 
# TO ADD
#	- ???
##############################################################################

#region Configuration
	## Environment Specific - Change These ##
	$SMTPServer = "someserver"
	$FromAddress = "exchangereport@localhost"
	$ToAddress = "yourname@yourorganization.com"
	$MessageSubject = "Exchange 2010 Troubleshooter Alert"
	$TestingMode = $true		# If true this will run tests without making any changes
					#  it will also send the entire report, including
					#  informational events. This is good to test your
					#  smtp relay configuration.
					#  (Note: the database size and latency troubleshooters WILL make
					#   some changes regardless of the value of this setting so make sure
					#	that $TroubleshootDBSpace and $TroubleshootDBLatency are set to
					#	$false if in testing mode.)
	$QuarantineHeavyUsers = $false	# Database latency/space testing has the option of quarantining heavy users.
					#  By default this is disabled as it can unexpectedly and adversly
					#  affect user access. But if you don't care then enable this as a 
					#  possible stop-gap mechanism for helping reduce performance
					#  issues or running out of database space. This will teach users
					#  not to send 10Mb attachements to large distribuation lists!
	$SendEmailAlert = $true		# Send alert if any errors/warnings come up in the troubleshooting
	$SendSystemReport = $true	# If true this will additionally send an additional system report
					#  Requires MS Chart Controls for .Net 3.5
					#  http://www.microsoft.com/download/en/details.aspx?id=14422
	$Redistribute = $false		# Automatically redistribute DAG databases (by activation preference)
	$TroubleshootCI = $true		# Automatically troubleshoot and attempt to resolve content index issues
	$TroubleshootDBLatency = $true	# Troubleshoot database latency issues
	$TroubleshootDBSpace = $true	# Troubleshoot database space issues
	$EventNum = 3			# Number of events to fetch for system report
	$ProccessNumToFetch = 10	# Number of processes to fetch for system report
	
	## Required - Leave These Alone ##
	# Exchange 2010 Path/Directories
	$ExchPath = $Env:ExchangeInstallPath
	# Event IDs which indicate issues of some sort
	$BadInstances = @("5300","5301","5302","5600","5601","5602","5603","5604","5605","6600","6601","5400","5401","5410","5700","5701","5702","5411","5412","5710","5712")

	# System and Error Report Headers
	$ErrorReport = @'
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=iso-8859-1'>
<title>OAB Events Report</title>
<STYLE TYPE="text/css">
<!--
td {
font-family: Tahoma;
font-size: 12px;
border-top: 1px solid #999999;
border-right: 1px solid #999999;
border-bottom: 1px solid #999999;
border-left: 1px solid #999999;
padding-top: 0px;
padding-right: 0px;
padding-bottom: 0px;
padding-left: 0px;
}
.Headings {
font-family: Tahoma;
font-size: 14px;
font-weight: bold;
}
body {
margin-left: 5px;
margin-top: 5px;
margin-right: 0px;
margin-bottom: 10px;
table {
border: thin solid #000000;
}
-->
</style>
</head>
<body>
<table width='100%'>
<tr bgcolor='#3366FF'>
<td colspan='7' height='25' align='left'>
<font face='tahoma' color='#FFFFFF' size='4'><strong>Exchange Error Log</strong></font>
</td>
</tr>
</table>
<p class=headings>Event Logs</p>
<table>
<tr>
<td><strong>Event ID</strong></td>
<td><strong>Time Generated</strong></td>
<td><strong>Machine Name</strong></td>
<td><strong>Category</strong></td>
<td><strong>Entry Type</strong></td>
<td><strong>Message</strong></td>
</tr>
'@
	$HTMLHeader = @"
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Frameset//EN" "http://www.w3.org/TR/html4/frameset.dtd">
<html><head><title>My Systems Report</title>
<style type="text/css">
<!--
body {
font-family: Verdana, Geneva, Arial, Helvetica, sans-serif;
}

    #report { width: 835px; }

    table{
	border-collapse: collapse;
	border: none;
	font: 10pt Verdana, Geneva, Arial, Helvetica, sans-serif;
	color: black;
	margin-bottom: 10px;
}

    table td{
	font-size: 12px;
	padding-left: 0px;
	padding-right: 20px;
	text-align: left;
}

    table th {
	font-size: 12px;
	font-weight: bold;
	padding-left: 0px;
	padding-right: 20px;
	text-align: left;
}

h2{ clear: both; font-size: 130%; }

h3{
	clear: both;
	font-size: 115%;
	margin-left: 20px;
	margin-top: 30px;
}

p{ margin-left: 20px; font-size: 12px; }

table.list{ float: left; }

    table.list td:nth-child(1){
	font-weight: bold;
	border-right: 1px grey solid;
	text-align: right;
}

table.list td:nth-child(2){ padding-left: 7px; }
table tr:nth-child(even) td:nth-child(even){ background: #CCCCCC; }
table tr:nth-child(odd) td:nth-child(odd){ background: #F2F2F2; }
table tr:nth-child(even) td:nth-child(odd){ background: #DDDDDD; }
table tr:nth-child(odd) td:nth-child(even){ background: #E5E5E5; }
div.column { width: 320px; float: left; }
div.first{ padding-right: 20px; border-right: 1px  grey solid; }
div.second{ margin-left: 30px; }
table{ margin-left: 20px; }
-->
</style>
</head>
<body>

"@
	$HTMLEnd = @"
</div>
</body>
</html>
"@

	$ListOfAttachments = @()
	$Report = @()
	# Exchange 2010 Database Servers Only
	$Servers =  @(Get-MailboxServer | Where {$_.AdminDisplayVersion -like "Version 14*"})
	
	# Script Path/Directories
	$ScriptPath   	= (Split-Path ((Get-Variable MyInvocation).Value).MyCommand.Path)
	$ScriptPluginPath	= $ScriptOutput + "\plugin\"
	$ScriptToolsPath	= $ScriptOutput + "\tools\"
	$ScriptOutputPath	= $ScriptOutput + "\Output\"
	
	# Date Format
	$DateFormat		= Get-Date -Format "MM/dd/yyyy_HHmmss" 
#endregion
#region Module/Snapin/Dot Sourcing
	if (! (Get-PSSnapin Microsoft.Exchange.Management.PowerShell.E2010 -ErrorAction:SilentlyContinue) )
		{ Add-PSSnapin Microsoft.Exchange.Management.PowerShell.E2010 }
 # REQUIREMENTS
 #requires -PsSnapIn Microsoft.Exchange.Management.PowerShell.E2010 -Version 2
   
#endregion
#region help
<#
.SYNOPSIS
	Troubleshoot-MailboxDatabase.ps1
.DESCRIPTION
	This script is meant for locally automating the following
	troubleshooting scripts found in %ExchangeInstallPath%Scripts\ and
	optionally emailing a warning/error color coded report upon completion:
		Troubleshoot-CI.ps1
		Troubleshoot-DatabaseLatency.ps1 (http://technet.microsoft.com/en-us/library/ff798271)
		Troubleshoot-DatabaseSpace.ps1 (http://technet.microsoft.com/en-us/library/ff477617.aspx)
	
	This script will also optionally redistribute your DAG(s) with:
		RedistributeActiveDatabases.ps1
		
	More information about the Exchange 2010 Troubleshooters:
		http://blogs.technet.com/b/exchange/archive/2011/01/18/3411844.aspx
	
	Be cautioned that although this script does have a testing mode it does not prevent the
	troubleshooter scripts from disabling provisioning of mailboxes to databases as that feature
	is not available as part of the troubleshooter scripts. Should you find that databases have
	become unprovisionable and you want the ability to provision to them again you need to run the
	following from an exchange 2010 management shell:
		Set-MailboxDatabase <database name> -IsExcludedFromProvisioning:$false
		
.PARAMETER
	<none>
.INPUTS
	<none>
.OUTPUTS
	<none>
.EXAMPLE
	Run stand alone
		Exchange2010Monitoring.ps1
	Schedule as a task
		cd $exscripts
		ManageScheduledTask.ps1 -Install –ServerName <Your Server> -PsScriptPath C:\Scripts\Troubleshoot-MailboxServer.ps1
		 –TaskName "Troubleshoot Exchange 2010 Mailbox Servers"
		(Note: this adds the scheduled task as a generic task, you will still need to go into scheduled tasks
		 and set a schedule for it to run and add any details to the description)
.LINK
	http://zacharyloeber.com
#>
#endregion

#region functions
Function Create-PieChart() {
	param([string]$FileName)
		
	[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
	[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms.DataVisualization")
	
	#Create our chart object 
	$Chart = New-object System.Windows.Forms.DataVisualization.Charting.Chart 
	$Chart.Width = 300
	$Chart.Height = 290 
	$Chart.Left = 10
	$Chart.Top = 10

	#Create a chartarea to draw on and add this to the chart 
	$ChartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
	$Chart.ChartAreas.Add($ChartArea) 
	[void]$Chart.Series.Add("Data") 

	#Add a datapoint for each value specified in the arguments (args) 
    foreach ($value in $args[0]) {
		$datapoint = new-object System.Windows.Forms.DataVisualization.Charting.DataPoint(0, $value)
	    $datapoint.AxisLabel = "Value" + "(" + $value + " GB)"
	    $Chart.Series["Data"].Points.Add($datapoint)
	}

	$Chart.Series["Data"].ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Pie
	$Chart.Series["Data"]["PieLabelStyle"] = "Outside" 
	$Chart.Series["Data"]["PieLineColor"] = "Black" 
	$Chart.Series["Data"]["PieDrawingStyle"] = "Concave" 
	($Chart.Series["Data"].Points.FindMaxByValue())["Exploded"] = $true

	#Set the title of the Chart to the current date and time 
	$Title = new-object System.Windows.Forms.DataVisualization.Charting.Title 
	$Chart.Titles.Add($Title) 
	$Chart.Titles[0].Text = "RAM Usage Chart (Used/Free)"

	#Save the chart to a file
	$Chart.SaveImage($FileName + ".png","png")
}

Function Get-HostUptime {
	param ([string]$ComputerName)
	$Uptime = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $ComputerName
	$LastBootUpTime = $Uptime.ConvertToDateTime($Uptime.LastBootUpTime)
	$Time = (Get-Date) - $LastBootUpTime
	Return '{0:00} Days, {1:00} Hours, {2:00} Minutes, {3:00} Seconds' -f $Time.Days, $Time.Hours, $Time.Minutes, $Time.Seconds
}
#endregion
#region script
Foreach ($MailboxServer in $Servers) {
	$MailboxDatabases = Get-MailboxDatabase -Server $MailboxServer.Name
	# Troubleshoot content indexes and attempt to automatically resolve
	If ($TroubleshootCI) {
		$script = $ExchPath + "scripts\Troubleshoot-CI.ps1"
		If ($TestingMode) {
			&$script -Server $MailboxServer.Name -Action:Detect -ErrorAction:SilentlyContinue | out-null 
		}
		Else {
			&$script -Server $MailboxServer.Name -Action:DetectAndResolve -ErrorAction:SilentlyContinue | out-null 
		}
	}
	# Check database latency and space
	Foreach ($MailboxDatabase in $MailboxDatabases) {
		If ($TroubleshootDBLatency) {
			$script = $ExchPath + "scripts\Troubleshoot-DatabaseLatency.ps1" 
			If ($TestingMode) {
				&$script -MailboxDatabaseName $MailboxDatabase.Name -Quarantine:$False `
				-ErrorAction:SilentlyContinue | out-null
			}
			Else {
				&$script -MailboxDatabaseName $MailboxDatabase.Name -Quarantine:$QuarantineHeavyUsers `
				-ErrorAction:SilentlyContinue | out-null
			}
		}		
		If ($TroubleshootDBSpace) {
			$script = $ExchPath + "scripts\Troubleshoot-DatabaseSpace.ps1"
			If ($TestingMode) {
				&$script -MailboxDatabaseName $MailboxDatabase.Name -Quarantine:$False `
				-ErrorAction:SilentlyContinue | out-null
			}
			Else {
				&$script -MailboxDatabaseName $MailboxDatabase.Name -Quarantine:$QuarantineHeavyUsers `
				-ErrorAction:SilentlyContinue | out-null
			}
		}
	}
}
# Redistribute Databases on Dags
If ($Redistribute -and !$TestingMode) {
	$script = $ExchPath + "scripts\RedistributeActiveDatabases.ps1"
	ForEach ($DAG in (Get-DatabaseAvailabilityGroup)) {
		&$script -DagName $DAG.Name -BalanceDbsByActivationPreference | out-null
	}
}

# Send an email if errors have occurred.
If ($SendEmailAlert) {
	If ($TestingMode) {
		$Events = @((Get-EventLog -log 'Microsoft-Exchange-Troubleshooters/Operational' `
		-after ((get-date).addDays(-1))))
    }
	Else {
		$Events = @((Get-EventLog -log 'Microsoft-Exchange-Troubleshooters/Operational' `
		-after ((get-date).addDays(-1))) | where {($BadInstances -contains $_.InstanceID)})
	}
      ForEach ($Event in $Events)
      {
	       $evtID = $Event.EventID
	       $evtTime = $Event.TimeGenerated
	       $evtMachine = $Event.MachineName
	       $evtCat = $Event.Category
	       $evtType = $Event.EntryType
		   $evtMessage = $Event.Message
        
	       if($evtType -eq 'Error'){
	           $ErrorReport += "<tr bgcolor=""#FF0000"">"
	           $ErrorReport += "<td>$evtID</td>"
	           $ErrorReport += "<td>$evtTime</td>"
	           $ErrorReport += "<td>$evtMachine</td>"
	           $ErrorReport += "<td>$evtCat</td>"
	           $ErrorReport += "<td>$evtType</td>"
	           $ErrorReport += "<td>$evtMessage</td>"
	           $ErrorReport += "</tr>"
	       }elseif($evtType -eq 'Warning'){
	           $ErrorReport += "<tr bgcolor=""#FFA500"">"
	           $ErrorReport += "<td>$evtID</td>"
	           $ErrorReport += "<td>$evtTime</td>"
	           $ErrorReport += "<td>$evtMachine</td>"
	           $ErrorReport += "<td>$evtCat</td>"
	           $ErrorReport += "<td>$evtType</td>"
	           $ErrorReport += "<td>$evtMessage</td>"
	           $ErrorReport += "</tr>"
	       }else{         
	           $ErrorReport += "<tr>"
	           $ErrorReport += "<td>$evtID</td>"
	           $ErrorReport += "<td>$evtTime</td>"
	           $ErrorReport += "<td>$evtMachine</td>"
	           $ErrorReport += "<td>$evtCat</td>"
	           $ErrorReport += "<td>$evtType</td>"
	           $ErrorReport += "<td>$evtMessage</td>"
	           $ErrorReport += "</tr>"
	       }
    }
	$ErrorReport += "</table>"
	$ErrorReport += "</body>"
	$ErrorReport += "</html>"
	if ($Events.Count -gt 0) {
		send-mailmessage -from $FromAddress -to $ToAddress -subject $MessageSubject `
		-BodyAsHTML -Body $ErrorReport -priority Normal -smtpServer $SMTPServer
		# This generates an overall system report and sends it in a separate email.
		If ($SendSystemReport) {
			Foreach ($MailboxServer in $Servers) {
				$DiskInfo= Get-WMIObject -ComputerName $MailboxServer.Name Win32_LogicalDisk | Where-Object{$_.DriveType -eq 3} `
				| Select-Object SystemName, `
								DriveType, `
								VolumeName, `
								Name, `
								@{n='Size (GB)';e={"{0:n2}" -f ($_.size/1gb)}}, `
								@{n='FreeSpace (GB)';e={"{0:n2}" -f ($_.freespace/1gb)}}, `
								@{n='PercentFree';e={"{0:n2}" -f ($_.freespace/$_.size*100)}} | ConvertTo-HTML -fragment
				
				#region System Info
				$OS = (Get-WmiObject Win32_OperatingSystem -computername $MailboxServer.Name).caption
				$SystemInfo = Get-WmiObject -Class Win32_OperatingSystem -computername $MailboxServer.Name | Select-Object Name, TotalVisibleMemorySize, FreePhysicalMemory
				$TotalRAM = $SystemInfo.TotalVisibleMemorySize/1MB
				$FreeRAM = $SystemInfo.FreePhysicalMemory/1MB
				$UsedRAM = $TotalRAM - $FreeRAM
				$RAMPercentFree = ($FreeRAM / $TotalRAM) * 100
				$TotalRAM = [Math]::Round($TotalRAM, 2)
				$FreeRAM = [Math]::Round($FreeRAM, 2)
				$UsedRAM = [Math]::Round($UsedRAM, 2)
				$RAMPercentFree = [Math]::Round($RAMPercentFree, 2)
				#endregion
				
				$TopProcesses = Get-Process -ComputerName $MailboxServer.Name | Sort WS -Descending | `
					Select ProcessName, Id, WS -First $ProccessNumToFetch | ConvertTo-Html -Fragment
				
				#region Services Report
				$ServicesReport = @()
				$Services = Get-WmiObject -Class Win32_Service -ComputerName $MailboxServer.Name | `
					Where {($_.StartMode -eq "Auto") -and ($_.State -eq "Stopped")}

				foreach ($Service in $Services) {
					$row = New-Object -Type PSObject -Property @{
				   		Name = $Service.Name
						Status = $Service.State
						StartMode = $Service.StartMode
					}
					
				$ServicesReport += $row
				
				}
				
				$ServicesReport = $ServicesReport | ConvertTo-Html -Fragment
				#endregion
					
				#region Event Logs Report
				$SystemEventsReport = @()
				$SystemEvents = Get-EventLog -ComputerName $MailboxServer.Name -LogName System -EntryType Error,Warning -Newest $EventNum
				foreach ($event in $SystemEvents) {
					$row = New-Object -Type PSObject -Property @{
						TimeGenerated = $event.TimeGenerated
						EntryType = $event.EntryType
						Source = $event.Source
						Message = $event.Message
					}
					$SystemEventsReport += $row
				}
						
				$SystemEventsReport = $SystemEventsReport | ConvertTo-Html -Fragment
				
				$ApplicationEventsReport = @()
				$ApplicationEvents = Get-EventLog -ComputerName $MailboxServer.Name -LogName Application -EntryType Error,Warning -Newest $EventNum
				foreach ($event in $ApplicationEvents) {
					$row = New-Object -Type PSObject -Property @{
						TimeGenerated = $event.TimeGenerated
						EntryType = $event.EntryType
						Source = $event.Source
						Message = $event.Message
					}
					$ApplicationEventsReport += $row
				}
				
				$ApplicationEventsReport = $ApplicationEventsReport | ConvertTo-Html -Fragment
				#endregion
				
				# Create the chart using our Chart Function
				Create-PieChart -FileName ((Get-Location).Path + "\chart-$MailboxServer.Name") $FreeRAM, $UsedRAM
				$ListOfAttachments += "chart-$MailboxServer.Name.png"
				#region Uptime
				# Fetch the Uptime of the current system using our Get-HostUptime Function.
				$SystemUptime = Get-HostUptime -ComputerName $MailboxServer.Name
				#endregion

				# Create HTML Report for the current System being looped through
				$CurrentSystemHTML = @"
				<hr noshade size=3 width="100%">
				<div id="report">
				<p><h2>$MailboxServer.Name Report</p></h2>
				<h3>System Info</h3>
				<table class="list">
				<tr>
				<td>System Uptime</td>
				<td>$SystemUptime</td>
				</tr>
				<tr>
				<td>OS</td>
				<td>$OS</td>
				</tr>
				<tr>
				<td>Total RAM (GB)</td>
				<td>$TotalRAM</td>
				</tr>
				<tr>
				<td>Free RAM (GB)</td>
				<td>$FreeRAM</td>
				</tr>
				<tr>
				<td>Percent free RAM</td>
				<td>$RAMPercentFree</td>
				</tr>
				</table>
				
				<IMG SRC="chart-$MailboxServer.Name.png" ALT="$MailboxServer.Name Chart">
					
				<h3>Disk Info</h3>
				<p>Drive(s) listed below have less than $thresholdspace % free space. Drives above this threshold will not be listed.</p>
				<table class="normal">$DiskInfo</table>
				<br></br>
				
				<div class="first column">
				<h3>System Processes - Top $ProccessNumToFetch Highest Memory Usage</h3>
				<p>The following $ProccessNumToFetch processes are those consuming the highest amount of Working Set (WS) Memory (bytes) on $MailboxServer.Name</p>
				<table class="normal">$TopProcesses</table>
				</div>
				<div class="second column">
				
				<h3>System Services - Automatic Startup but not Running</h3>
				<p>The following services are those which are set to Automatic startup type, yet are currently not running on $MailboxServer</p>
				<table class="normal">
				$ServicesReport
				</table>
				</div>
				
				<h3>Events Report - The last $EventNum System/Application Log Events that were Warnings or Errors</h3>
				<p>The following is a list of the last $EventNum <b>System log</b> events that had an Event Type of either Warning or Error on $MailboxServer.Name</p>
				<table class="normal">$SystemEventsReport</table>

				<p>The following is a list of the last $EventNum <b>Application log</b> events that had an Event Type of either Warning or Error on $MailboxServer.Name</p>
				<table class="normal">$ApplicationEventsReport</table>
"@
				# Add the current System HTML Report into the final HTML Report body
				$HTMLMiddle += $CurrentSystemHTML
				
				}
		}
		# Assemble the final report from all our HTML sections
		$HTMLmessage = $HTMLHeader + $HTMLMiddle + $HTMLEnd
		# Save the report out to a file in the current path
		$HTMLmessage | Out-File ((Get-Location).Path + "\report.html")
		# Email our report out
		send-mailmessage -from $FromAddress -to $ToAddress -subject "Mailbox Server Report" `
		-Attachments $ListOfAttachments -BodyAsHTML -Body $HTMLmessage -priority Normal -smtpServer $SMTPServer
	}
}
#endregion