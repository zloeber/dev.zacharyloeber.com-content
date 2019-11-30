<#
 Exchange 2010 Client Access Report Generation Script
 Author:	Zachary Loeber
 Date:		01/16/2012 
 Version:	1.0
 Description:
 Requirements:
	
 Example:
 	./Get-ExchangeCASURLs.ps1 -OutputFile "./CAS-Access.csv"
 Notes:
	I welcome recommendations or corrections zloeber (at) gmail (dot) com
 Change Log:
	1.0 - Initial release
	1.1 - Change output formatting
		Possible Authentication Settings: Basic Ntlm WindowsIntegrated WSSecurity Fba
		Split output into three tables
	Future Additions?
		Autodiscover Internal URL
		Spit out Outlook provider settings
		Get certificates and associated services, common name, and SAN names
		Got rid of the IIS path, saw no real need for it from a documentation standpoint

#>
param([parameter(Mandatory=$true,ValueFromPipeline=$false,HelpMessage="Output CSV File")][string]$OutputFile)

function GetVdirAuth {
	<#
	.SYNOPSIS
	   Return true/false values for each type of IIS authentication found in a string
	.DESCRIPTION
	   Looks for the following auth types: Basic,Ntlm,Fba,WSSecurity,WindowsIntegrated
	.NOTES
	   Function Name : GetVdirAuth
	   Author : Zachary Loeber
	   Requires : PowerShell V2
	.LINK
	   http://zacharyloeber.com
	.EXAMPLE
	   Simple usage
	   PS C:\> GetVdirAuth("Ntlm Fba").Basic
	    False
	   PS C:\> GetVdirAuth("Ntlm Fba").Ntlm
	    True
	.PARAMETER AuthString
	   String with authentication types
	#>
	[CmdletBinding()]
    param(  
    	[Parameter(
    		Position=0, 
    		Mandatory=$true, 
    		ValueFromPipeline=$true,
    		ValueFromPipelineByPropertyName=$true)
    	]
		[AllowEmptyString()]
    	[Alias('FullAuthenticationStringName')]
    	[String[]]$AuthString)
	process {
		New-Object PSObject -Property @{
			"Basic" = [bool]@($AuthString -match "Basic") 
			"Ntlm" = [bool]@($AuthString -match "Ntlm")
			"WindowsIntegrated" = [bool]@($AuthString -match "WindowsIntegrated")
			"WSSecurity" = [bool]@($AuthString -match "WSSecurity")
			"Fba" = [bool]@($AuthString -match "Fba")
			}
		}
}

function Get-CASActiveUsers {
  [CmdletBinding()]
  param(
      [Parameter(Position=0, ParameterSetName="Value", Mandatory=$true)]
      [String[]]$ComputerName,
      [Parameter(Position=0, ParameterSetName="Pipeline", ValueFromPipelineByPropertyName=$true, Mandatory=$true)]
      [String]$Name
      )

  process {
    switch($PsCmdlet.ParameterSetName) {
      "Value" {$servers = $ComputerName}
      "Pipeline" {$servers = $Name}
    }
    $servers | %{
      $RPC = Get-Counter "\MSExchange RpcClientAccess\User Count" -ComputerName $_
      $OWA = Get-Counter "\MSExchange OWA\Current Unique Users" -ComputerName $_
      New-Object PSObject -Property @{
        Server = $_
        "RPC Client Access" = $RPC.CounterSamples[0].CookedValue
        "Outlook Web App" = $OWA.CounterSamples[0].CookedValue
      }
    }
  }
}

## Start Here ##

$CASAccessURLTable = @()
$CASAccessAuthTable = @()
$CASServers = Get-ClientAccessServer

# First lets get the collection of rules which only applies to the roles in the environment
Foreach ($CASServer in $CASServers) {
	# Autodiscover information
	Foreach ($AccessPath in (Get-AutodiscoverVirtualDirectory -Server $CASServer)) {
		$CASAccessURLS = New-Object Object
		$CASAccessAuth = New-Object Object
		$CASAccessURLS | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessAuth | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessURLs | Add-Member NoteProperty "Function" "Autodiscover";
		$CASAccessAuth | Add-Member NoteProperty "Function" "Autodiscover";
		$CASAccessURLS | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessAuth | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessURLS | Add-Member NoteProperty "Internal URL" $AccessPath.InternalURL;
		$CASAccessURLS | Add-Member NoteProperty "External URL" $AccessPath.ExternalURL;
		#Get access methods
		$IntAuth = GetVdirAuth (($AccessPath.InternalAuthenticationMethods | Out-String))
		$ExtAuth = GetVdirAuth (($AccessPath.ExternalAuthenticationMethods | Out-String))
		$CASAccessAuth | Add-Member NoteProperty "InternalAuth" $IntAuth.ntlm
		$CASAccessAuth | Add-Member NoteProperty "ExternalAuth" $ExtAuth
		$CASAccessURLTable += $CASAccessURLS
		$CASAccessAuthTable += $CASAccessAuth
	}
	
	# OWA information
	Foreach ($AccessPath in (Get-OWAVirtualDirectory -Server $CASServer)) {
		$CASAccessURLS = New-Object Object
		$CASAccessAuth = New-Object Object
		$CASAccessURLS | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessAuth | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessURLs | Add-Member NoteProperty "Function" "OWA";
		$CASAccessAuth | Add-Member NoteProperty "Function" "OWA";
		$CASAccessURLS | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessAuth | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessURLS | Add-Member NoteProperty "Internal URL" $AccessPath.InternalURL;
		$CASAccessURLS | Add-Member NoteProperty "External URL" $AccessPath.ExternalURL;
		#Get access methods
		$IntAuth = GetVdirAuth (($AccessPath.InternalAuthenticationMethods | Out-String))
		$ExtAuth = GetVdirAuth (($AccessPath.ExternalAuthenticationMethods | Out-String))
		$CASAccessAuth | Add-Member NoteProperty "InternalAuth" $IntAuth
		$CASAccessAuth | Add-Member NoteProperty "ExternalAuth" $ExtAuth
		$CASAccessURLTable += $CASAccessURLS
		$CASAccessAuthTable += $CASAccessAuth
	}
	
	#ECP information
	Foreach ($AccessPath in (Get-ECPVirtualDirectory -Server $CASServer)) {
		$CASAccessURLS = New-Object Object
		$CASAccessAuth = New-Object Object
		$CASAccessURLS | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessAuth | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessURLs | Add-Member NoteProperty "Function" "ECP";
		$CASAccessAuth | Add-Member NoteProperty "Function" "ECP";
		$CASAccessURLS | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessAuth | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessURLS | Add-Member NoteProperty "Internal URL" $AccessPath.InternalURL;
		$CASAccessURLS | Add-Member NoteProperty "External URL" $AccessPath.ExternalURL;
		#Get access methods
		$IntAuth = GetVdirAuth (($AccessPath.InternalAuthenticationMethods | Out-String))
		$ExtAuth = GetVdirAuth (($AccessPath.ExternalAuthenticationMethods | Out-String))
		$CASAccessAuth | Add-Member NoteProperty "InternalAuth" $IntAuth
		$CASAccessAuth | Add-Member NoteProperty "ExternalAuth" $ExtAuth
		$CASAccessURLTable += $CASAccessURLS
		$CASAccessAuthTable += $CASAccessAuth
	}
	
	#OAB information
	Foreach ($AccessPath in (Get-OABVirtualDirectory -Server $CASServer)) {
		$CASAccessURLS = New-Object Object
		$CASAccessAuth = New-Object Object
		$CASAccessURLS | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessAuth | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessURLs | Add-Member NoteProperty "Function" "OAB";
		$CASAccessAuth | Add-Member NoteProperty "Function" "OAB";
		$CASAccessURLS | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessAuth | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessURLS | Add-Member NoteProperty "Internal URL" $AccessPath.InternalURL;
		$CASAccessURLS | Add-Member NoteProperty "External URL" $AccessPath.ExternalURL;
		#Get access methods
		$IntAuth = GetVdirAuth (($AccessPath.InternalAuthenticationMethods | Out-String))
		$ExtAuth = GetVdirAuth (($AccessPath.ExternalAuthenticationMethods | Out-String))
		$CASAccessAuth | Add-Member NoteProperty "InternalAuth" $IntAuth
		$CASAccessAuth | Add-Member NoteProperty "ExternalAuth" $ExtAuth
		$CASAccessURLTable += $CASAccessURLS
		$CASAccessAuthTable += $CASAccessAuth
	}
	
	# Web Services
	Foreach ($AccessPath in (Get-WebServicesVirtualDirectory -Server $CASServer)) {
		$CASAccessURLS = New-Object Object
		$CASAccessAuth = New-Object Object
		$CASAccessURLS | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessAuth | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessURLs | Add-Member NoteProperty "Function" "EWS";
		$CASAccessAuth | Add-Member NoteProperty "Function" "EWS";
		$CASAccessURLS | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessAuth | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessURLS | Add-Member NoteProperty "Internal URL" $AccessPath.InternalURL;
		$CASAccessURLS | Add-Member NoteProperty "External URL" $AccessPath.ExternalURL;
		#Get access methods
		$IntAuth = GetVdirAuth (($AccessPath.InternalAuthenticationMethods | Out-String))
		$ExtAuth = GetVdirAuth (($AccessPath.ExternalAuthenticationMethods | Out-String))
		$CASAccessAuth | Add-Member NoteProperty "InternalAuth" $IntAuth
		$CASAccessAuth | Add-Member NoteProperty "ExternalAuth" $ExtAuth
		$CASAccessURLTable += $CASAccessURLS
		$CASAccessAuthTable += $CASAccessAuth
	}
	
	# ActiveSync 
	Foreach ($AccessPath in (Get-ActiveSyncVirtualDirectory -Server $CASServer)) {
		$CASAccessURLS = New-Object Object
		$CASAccessAuth = New-Object Object
		$CASAccessURLS | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessAuth | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessURLs | Add-Member NoteProperty "Function" "ActiveSync";
		$CASAccessAuth | Add-Member NoteProperty "Function" "ActiveSync";
		$CASAccessURLS | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessAuth | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessURLS | Add-Member NoteProperty "Internal URL" $AccessPath.InternalURL;
		$CASAccessURLS | Add-Member NoteProperty "External URL" $AccessPath.ExternalURL;
		#Get access methods
		$IntAuth = GetVdirAuth (($AccessPath.InternalAuthenticationMethods | Out-String))
		$ExtAuth = GetVdirAuth (($AccessPath.ExternalAuthenticationMethods | Out-String))
		$CASAccessAuth | Add-Member NoteProperty "InternalAuth" $IntAuth
		$CASAccessAuth | Add-Member NoteProperty "ExternalAuth" $ExtAuth
		$CASAccessURLTable += $CASAccessURLS
		$CASAccessAuthTable += $CASAccessAuth
	}
	
	# Powershell
	Foreach ($AccessPath in (Get-PowershellVirtualDirectory -Server $CASServer)) {
		$CASAccessURLS = New-Object Object
		$CASAccessAuth = New-Object Object
		$CASAccessURLS | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessAuth | Add-Member NoteProperty "Server" $AccessPath.Server;
		$CASAccessURLs | Add-Member NoteProperty "Function" "Powershell";
		$CASAccessAuth | Add-Member NoteProperty "Function" "Powershell";
		$CASAccessURLS | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessAuth | Add-Member NoteProperty "Name" $AccessPath.Name;
		$CASAccessURLS | Add-Member NoteProperty "Internal URL" $AccessPath.InternalURL;
		$CASAccessURLS | Add-Member NoteProperty "External URL" $AccessPath.ExternalURL;
		#Get access methods
		$IntAuth = GetVdirAuth (($AccessPath.InternalAuthenticationMethods | Out-String))
		$ExtAuth = GetVdirAuth (($AccessPath.ExternalAuthenticationMethods | Out-String))
		$CASAccessAuth | Add-Member NoteProperty "InternalAuth" $IntAuth
		$CASAccessAuth | Add-Member NoteProperty "ExternalAuth" $ExtAuth
		$CASAccessURLTable += $CASAccessURLS
		$CASAccessAuthTable += $CASAccessAuth
	}
}

$HTMLHead = @' 
	<style> 
	BODY{font-family:Verdana; background-color:#99CCCC;} 
	TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;} 
	TH{font-size:1.0em; border-width: 1px;padding: 2px;border-style: solid;border-color: black;background-color:#669999} 
	TD{border-width: 1px;padding: 2px;border-style: solid;border-color: black;background-color:#CCCCCC} 
	</style> 
'@ 
$HTMLTitle = "Client Access URLS" 
$FullReport = "<H1>Exchange Client Access Report</H1>"
$FullReport += "<H2>Client Access Paths</H2>"
$FullReport += ($CASAccessURLTable | select * | ConvertTo-HTML -fragment)
$FullReport += "<H2>Client Access Authentication</H2>"
$FullReport += "<H3>Internal Authentication</H3>"
$FullReport += ($CASAccessAuthTable | Select Server,Function,Name, `
	@{n='Basic';e={!$_.InternalAuth.Basic}},`
	@{n='NTLM';e={!$_.InternalAuth.NTLM}},`
	@{n='Windows Integrated';e={!$_.InternalAuth.WindowsIntegrated}},`
	@{n='Fba';e={!$_.InternalAuth.Fba}},`
	@{n='WSSecurity';e={!$_.InternalAuth.WSSecurity}} | ConvertTo-HTML -Fragment)
$FullReport += "<H3>External Authentication</H3>"
$FullReport += ($CASAccessAuthTable | Select Server,Function,Name, `
	@{n='Basic';e={!$_.ExternalAuth.Basic}},`
	@{n='NTLM';e={!$_.ExternalAuth.NTLM}},`
	@{n='Windows Integrated';e={!$_.ExternalAuth.WindowsIntegrated}},`
	@{n='Fba';e={!$_.ExternalAuth.Fba}},`
	@{n='WSSecurity';e={!$_.ExternalAuth.WSSecurity}} | ConvertTo-HTML -Fragment)

ConvertTo-Html -head $HTMLHead -title $HTMLTitle -Body $FullReport | Out-File -FilePath "./$OutputFile" 

& "./$OutputFile"