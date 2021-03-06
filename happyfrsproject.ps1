
$MyHostFile = "D:\\FRSVMlist-ver4.0-today.csv"
$MyOutput = "D:\\hellofrsresult-4-today.csv"
$tabName = "happyTable"

Function Parse-CSV {
    import-csv $MyHostFile -header Module,Hostname,IPAddress,OS,Account1,Password1,Account2,Password2,Account3,Password3 -delimiter ',' | Where-Object {$_.OS -match "Win"}
}

Function Get-Info($hostname, $Username, $Password, $classname) {
    Try {
        $CredUsername = "frsnet\" + $Username.trim()
        $Credential = new-object -typename System.Management.Automation.PSCredential -argumentlist $CredUsername, (ConvertTo-SecureString $Password.trim() -AsPlainText –Force)
        Get-WmiObject -class $classname -ComputerName $hostname -Namespace "root\cimv2" -Authentication 6 -Impersonation Impersonate -credential $Credential 
    }
    Catch {
        Write-Host "Get-WmiObject -class $classname -ComputerName $hostname -Namespace "root\cimv2" -Authentication 6 -Impersonation Impersonate -credential $Credential"
        $null
    }
}

Function Get-TimeZone($hostname, $Username, $Password) {
    Get-Info $hostname $Username $Password "win32_TimeZone"
}

Function Get-LocalTime($hostname, $Username, $Password) {
    $lt = Get-Info $hostname $Username $Password "Win32_LocalTime"
    if ($lt -ne $null) {
        Get-Date -Year $lt.Year -Month $lt.Month -Day $lt.Day -Hour $lt.Hour -Minute $lt.Minute -Second $lt.Second
    }
}

Function Get-CurrentTime($hostname, $Username, $Password) {
    $ct = Get-Info $hostname $Username $Password "Win32_UTCTime"
    if ($ct -ne $null) {
         Get-Date -Year $ct.Year -Month $ct.Month -Day $ct.Day -Hour $ct.Hour -Minute $ct.Minute -Second $ct.Second
    }
}

Function Check-RDP($hostname, $Username, $Password) {
    Write-Host "check $Username"
    [hashtable]$Return = @{} 
    if ($Username -and $Password) {
        $Return.Account = $Username
        $Return.Result = "Fail"
        Try {
            $CredUsername = "frsnet\" + $Username.trim()
            $Credential = new-object -typename System.Management.Automation.PSCredential -argumentlist $CredUsername, (ConvertTo-SecureString $Password.trim() -AsPlainText –Force)
            $wmi = Get-WmiObject -class "Win32_TSGeneralSetting" -ComputerName $hostname -Namespace "root\cimv2\terminalservices" -Authentication 6 -Impersonation Impersonate -credential $Credential -Filter "TerminalName='RDP-tcp'" 
            if ($wmi) {
                $Return.Result = "Success"
            } else {
                $Return.Result = "RPC unreachable"
            }
        }
        Catch {     
            $Return.Result = "Fail"        
        }
        return $Return
    }
}

Function Resolve-IP($ip) {
     $result = $null
    
     $currentEAP = $ErrorActionPreference
     $ErrorActionPreference = "silentlycontinue"
    
     #Use the DNS Static .Net class for the reverse lookup
     # details on this method found here: http://msdn.microsoft.com/en-us/library/ms143997.aspx
     $result = [System.Net.Dns]::gethostentry($ip)
    
     $ErrorActionPreference = $currentEAP
    
     If ($result)
     {
        [string]$Result.HostName
     }
     Else
     {
        $null    
     }
}

Function Resolve-Hostname($hostname) {
	 $result = $null
    
     $currentEAP = $ErrorActionPreference
     $ErrorActionPreference = "silentlycontinue"
    
     #Use the DNS Static .Net class for the reverse lookup
     # details on this method found here: http://msdn.microsoft.com/en-us/library/ms143997.aspx
     #$result = [System.Net.Dns]::gethostentry($ip)
     $result = [System.Net.Dns]::GetHostAddresses($hostname)
     $ErrorActionPreference = $currentEAP

     If ($result)
     {
        [string]$result
     }
     Else
     {
        $null    
     }
}

Function Check-IP($hostname, $ip) {
    $resolvehost = Resolve-IP $ip
    if ($hostname -eq $resolvehost) {
        "Success"
    } else {
        "$ip - No HostNameFound $hostname $resolvehost"
    }
}

Function Check-Hostname($hostname, $ip) {
    $resolveip = Resolve-Hostname $hostname

    if (($ip -eq $resolveip) -or (($resolveip -match ":") -and ($resolveip -match $ip))) {
        "Success"
    } else {
        "$hostname - No IP $ip $resolveip" 
    }
}


$CSV = Parse-CSV 
  
  
#Create Table object
$table = New-Object system.Data.DataTable “$tabName”

#Define Columns
$col1 = New-Object system.Data.DataColumn Hostname,([string])
$col2 = New-Object system.Data.DataColumn TimeZone,([string])
$col3 = New-Object system.Data.DataColumn CurrentTime,([string])
$col4 = New-Object system.Data.DataColumn LocalTime,([string])
$col5 = New-Object system.Data.DataColumn Account1,([string])
$col6 = New-Object system.Data.DataColumn Result1,([string])
$col7 = New-Object system.Data.DataColumn Account2,([string])
$col8 = New-Object system.Data.DataColumn Result2,([string])
$col9 = New-Object system.Data.DataColumn Account3,([string])
$col10 = New-Object system.Data.DataColumn Result3,([string])
$col11 = New-Object system.Data.DataColumn PTRRecord,([string])
$col12 = New-Object system.Data.DataColumn ARecord,([string])

#Add the Columns
ForEach($col in $col1, $col2, $col3, $col4, $col5, $col6, $col7, $col8, $col9, $col10, $col11, $col12) {
    $table.columns.add($col)
}


ForEach($c in $CSV) {
	#Write-Host $c
    
    #Create a row
    $row = $table.NewRow()

    $hostname = $c.Hostname.trim()
    $ip = $c.IPAddress.trim()
    $row.Hostname = $hostname
    $row.PTRRecord = Check-IP $hostname $ip
    $row.ARecord = Check-Hostname $hostname $ip
    
    $rdp1 = ""
    $rdp2 = ""
    $rdp3 = ""
    
    # check something if there is one set of account and password
    if ($c.Account1 -and $c.Password1) {
    	Write-Host $c
        
        $rdp1 = Check-RDP $hostname $c.Account1 $c.Password1
        Write-Host "First credential result - $rdp1.Result"
        
        # do things only if the first credential works
        if ($rdp1.Result -notmatch "unreachable") {
        
            Write-Host "check RDP"
            $rdp2 = Check-RDP $hostname $c.Account2 $c.Password2
            $rdp3 = Check-RDP $hostname $c.Account3 $c.Password3
            $timezone = Get-TimeZone $hostname $c.Account1 $c.Password1
            $localtime = Get-LocalTime $hostname $c.Account1 $c.Password1
            $currenttime = Get-CurrentTime $hostname $c.Account1 $c.Password1
        }
        
        #Enter data in the row
        
        $row.TimeZone = $timezone.Caption
        $row.CurrentTime = $currenttime
        $row.LocalTime = $localtime
        $row.Account1 = $c.Account1
        $row.Result1 = $rdp1.Result
        $row.Account2 = $c.Account2
        $row.Result2 = $rdp2.Result
        $row.Account3 = $c.Account3
        $row.Result3 = $rdp3.Result
        
	} else {
        $row.TimeZone = "Unable to reach out by empty username or password"
    }
    
    $table.Rows.Add($row)
    
    #Display the table
    $table | format-table -AutoSize

    #NOTE: Now you can also export this table to a CSV file as shown below.
    $tabCsv = $table | export-csv $MyOutput -noType
    #break
    
    
} 


