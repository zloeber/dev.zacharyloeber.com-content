function Colorize-Table 
{ 
[CmdletBinding(DefaultParameterSetName = "ObjectSet")] 
param ( 
    [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="ObjectSet")]
		[PSObject[]]$InputObject, 
	[Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="StringSet")] 
		[String[]]$InputString='', 
    [Parameter(Position=1, Mandatory=$true, ValueFromPipeline=$false)]
		[String]$Column, 
    [Parameter(Position=2, Mandatory=$true, ValueFromPipeline=$false)]
		$ColumnValue,
	[Parameter(Position=3, Mandatory=$false, ValueFromPipeline=$false)]
		[ScriptBlock]$ScriptBlock = {[string]$args[0] -eq [string]$args[1]}, 
	[Parameter(Position=4, Mandatory=$true, ValueFromPipeline=$false)] 
		[String]$Attr, 
    [Parameter(Position=5, Mandatory=$true, ValueFromPipeline=$false)] 
		[String]$AttrValue, 
    [Parameter(Position=6, Mandatory=$false, ValueFromPipeline=$false)] 
		[Bool]$WholeRow=$false, 
    [Parameter(Position=7, Mandatory=$false, ValueFromPipeline=$false, ParameterSetName="ObjectSet")] 
		[String]$HTMLHead='<title>HTML Table</title>') 

BEGIN 
{ 
    Add-Type -ErrorAction SilentlyContinue -Language CSharpVersion3 `
    -ReferencedAssemblies System.Xml, System.Xml.Linq `
    -UsingNamespace System.Linq `
    -Name XUtilities `
    -Namespace Huddled `
     -MemberDefinition @"
    public static System.Collections.Generic.IEnumerable<System.Xml.Linq.XElement> GetElementByIndex( System.Xml.Linq.XContainer doc, System.Xml.Linq.XName element, int index) { 
        return from e in doc.Descendants(element) where e.NodesBeforeSelf().Count() == index select e; 
    }
    public static System.Collections.Generic.IEnumerable<System.Xml.Linq.XElement> GetElementByValue( System.Xml.Linq.XContainer doc, System.Xml.Linq.XName element, string value) { 
        return from e in doc.Descendants(element) where e.Value == value select e; 
    }
"@ 
    $Objects = @() 
} 
 
PROCESS 
{ 
    # Handle passing object via pipe 
    $Objects += $InputObject 
} 
 
END 
{ 
	# Convert our data to x(ht)ml 
    if ($InputString)    # If a string was passed just parse it 
    { 
        $xml = [System.Xml.Linq.XDocument]::Parse("$InputString")  
    } 
    # Otherwise we have to convert it to html first 
	else
    { 
        $xml = [System.Xml.Linq.XDocument]::Parse("$($Objects | ConvertTo-Html -Head $HTMLHead)")     
    } 

    # Find the index of the column you want to format 
    $ColumnLoc = [Huddled.XUtilities]::GetElementByValue($xml, "{http://www.w3.org/1999/xhtml}th",$Column) 
    $ColumnIndex = $ColumnLoc | Foreach-Object{($_.NodesBeforeSelf() | Measure-Object).Count} 
    
    # Process each xml element based on the index for the column we are highlighting 
    switch([Huddled.XUtilities]::GetElementByIndex($xml, "{http://www.w3.org/1999/xhtml}td", $ColumnIndex)) 
    { 
		{$(Invoke-Command $ScriptBlock -ArgumentList @($_.Value, $ColumnValue))} {
			if ($WholeRow)
			{
				$_.Parent.SetAttributeValue($Attr, $AttrValue)
			}
			else
			{
				$_.SetAttributeValue($Attr, $AttrValue)
			}	
		}
    } 
    Return $xml.Document.ToString() 
}  
<# 
.SYNOPSIS 
Colorize-Table 
 
.DESCRIPTION 
Colorize cells of an array of objects. Otherwise, if an html table is passed through then colorize 
individual cells of it based on row header and value. 
 
.PARAMETER  InputObject 
An array of objects (ie. (Get-process | select Name,Company) 
 
.PARAMETER  Column 
The column you want to modify

.PARAMETER ScriptBlock
Used to perform custom cell evaluations such as -gt -lt or anything else you need to check for in a
table cell element. The scriptblock must return either $true or $false and is, by default, just
a basic -eq comparisson. You must use the variables as they are used in the following example.

[scriptblock]$scriptblock = {[int]$args[0] -gt [int]$args[1]}

$args[0] will be the cell value in the table
$args[1] will be the value to compare it to

Strong typesetting is encouraged for accuracy.

.PARAMETER  ColumnValue 
The column value you will modify if found. 
 
.PARAMETER  Attr 
The attribute to change should ColumnValue be found in the Column specified. 
- A good example is using "style" 
 
.PARAMETER  AttrValue 
The attribute value to set when the ColumnValue is found in the Column specified 
- A good example is using "background: red;" 
 
.EXAMPLE 
This will highlight the process name of Dropbox with a red background. 

$TableStyle = @'
<title>Process Report</title> 
	<style>             
	BODY{font-family: Arial; font-size: 8pt;} 
	H1{font-size: 16px;} 
	H2{font-size: 14px;} 
	H3{font-size: 12px;} 
	TABLE{border: 1px solid black; border-collapse: collapse; font-size: 8pt;} 
	TH{border: 1px solid black; background: #dddddd; padding: 5px; color: #000000;} 
	TD{border: 1px solid black; padding: 5px;} 
	</style>
'@

$tabletocolorize = $(Get-Process | ConvertTo-Html -Head $TableStyle) 
$colorizedtable = Colorize-Table $tabletocolorize -Column "Name" -ColumnValue "Dropbox" -Attr "style" -AttrValue "background: red;"
$colorizedtable | Out-File "$pwd/testreport.html" 
ii "$pwd/testreport.html"
  
.EXAMPLE 
Using the same $TableStyle variable above this will create a table of top 5 processes by memory usage,
color the background of a whole row yellow for any process using over 150Mb and red if over 400Mb.

$tabletocolorize = $(get-process | select -Property ProcessName,Company,@{Name="Memory";Expression={[math]::truncate($_.WS/ 1Mb)}} | Sort-Object Memory -Descending | Select -First 5 ) 

[scriptblock]$scriptblock = {[int]$args[0] -gt [int]$args[1]}
$testreport = Colorize-Table $tabletocolorize -Column "Memory" -ColumnValue 150 -Attr "style" -AttrValue "background:yellow;" -ScriptBlock $ScriptBlock -HTMLHead $TableStyle -WholeRow $true
$testreport = Colorize-Table $testreport -Column "Memory" -ColumnValue 400 -Attr "style" -AttrValue "background:red;" -ScriptBlock $ScriptBlock -WholeRow $true
$testreport | Out-File "$pwd/testreport.html" 
ii "$pwd/testreport.html"

.NOTES 
If you are going to convert something to html with convertto-html in powershell v2 there is a bug where the  
header will show up as an asterick if you only are converting one object property. 

This script is a modification of something I found by some rockstar named Jaykul at this site
http://stackoverflow.com/questions/4559233/technique-for-selectively-formatting-data-in-a-powershell-pipeline-and-output-as

I believe that .Net 4.0 is a requirement for using the Linq libraries

.LINK 
http://zacharyloeber.com 
#> 
}