## Cloudflare Bulk domain importer and redirector script
# V1.0 by Grahame Petch (20220202)
# V1.1 By Charly Dwyer (20220302)



## Change the following 3 values and populate with CloudFlare information known
##
## CFAccountID - open any site in the Account and it will show on the Overview page
## CFDomainEmail - what you use to login to Cloudflare
## CFAuthKey - Global API Key
## IPAddress - What the A Record for the domains should be set to

$CFAccountID=""
$CFDomainEmail=""
$CFAuthKey=""

$BaseURI="https://api.cloudflare.com/client/v4/zones"
$HeaderEmail = "X-Auth-Email: "+$CFDomainEmail
$HeaderAuthKey = "X-Auth-Key: "+$CFAuthKey

$Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]" #Set the Header string for the RestMethod / Curl call
$Headers.Add("X-Auth-Email", "$CFDomainEmail") #Set the Auth Email in the Headers of the call
$Headers.Add("X-Auth-Key", "$CFAuthKey") #Set the Auth Key in the Headers of the call

$IPAddress = ""

$DomainList = import-csv pathtofile\filename


Function AddZone{

    ## Adds a new zone to an existing Cloudflare account
    ## Parameter input is a domain name
    ## Returns a result containing the new Zone ID from Cloudflare

    Param(
      [Parameter(Mandatory=$True)]
      [String] $NewSite)

    $NewSite_ID=""

    $Body='"{\"name\":\"'+$NewSite+'\",\"account\":{\"id\":\"'+$CFAccountID+'\"},\"jump_start\":true,\"type\":\"full\"}"'
    $AddSiteResult = (curl.exe -X POST -H $HeaderEmail -H $HeaderAuthKey -H "Content-Type: application/json" --data $Body $BaseURI)
    return ($AddSiteResult)
}


Function AddRedirection{

## Adds a permanent redirection rule for the root of the domain specified
## Parameter input is the domain name to be forwarded (same as the domain name specified in the AddZone function), the zone ID returned from the AddZone function and the full URL and page suffix to redirect to
## Returns a result containing the full result of the command execution

Param([string]$New_Domain,[string]$Zone_ID,[string]$ForwardingURL)


$NewRuleResult=""

$RedirBody='{\"targets\":[{\"target\":\"url\",\"constraint\":{\"operator\":\"matches\",\"value\":\"*.'+$New_Domain+'\"}}],\"actions\":[{\"id\":\"forwarding_url\",\"value\":{\"url\":\"'+$ForwardingURL+'\",\"status_code\":301}}],\"priority\":1,\"status\":\"active\"}"'

$RulesURI=$BaseURI+'/'+$Zone_ID+'/pagerules'

$NewRuleResult = (curl.exe $RulesURI -X POST -H $HeaderEmail -H $HeaderAuthKey -H "Content-Type: application/json" --data $RedirBody)

return $NewRuleResult

}

Function GetDZid{ #Called to find the ZoneID of the domain we're working with.

  Param(
    [Parameter(Mandatory=$True)]
    [String] $zone)

  #Thanks to https://www.powershellgallery.com/packages/Posh-ACME/2.0/Content/DnsPlugins%5CCloudflare.ps1 for base code for this.
  $zoneid=invoke-restmethod  -method get -uri $BaseURI"/?per_page=1000&order=type&direction=asc" -Headers $Headers #make the request
  $allzones = $zoneid.result #Get all the zones in the results
  $totalzones = $zoneid.result_info.count #Get the total number of zones in the result
  $targetdomain = $zoneid.result | Where-Object {$_.name -eq "$zone"}  #Now the work begins. Select the domain we're looking for using the domainname.
  $targetdomainzid = $targetdomain.id
  return $targetdomainzid
}

Function GetDNSZones { #Find the Zones for an existing domain
  Param(
    [Parameter(Mandatory=$True)]
    [String] $ZoneID)

    $allrecords=invoke-restmethod  -method get -uri $BaseURI"/$($ZoneID)/dns_records?per_page=1000&order=type&direction=asc&match=all" -Headers $Headers
    return $allrecords
}

Function ADDIPAddress {

  Param(
    [Parameter(Mandatory=$True)]
    [String] $ZoneID)

    $Body = @{
        type = "A"
        name = "$NewDomain"
        content = "$IPAddress"
        proxied = $true
    }

    $JSONData = $Body | ConvertTo-Json
    $JSONResult = invoke-restmethod  -method Post -uri $BaseURI"/$($ZoneID)/dns_records"  -ContentType "application/json"  -Headers $Headers -Body $jsondata
    return $JSONResult.success
}


Function ChangeProxy {

  Param(
    [Parameter(Mandatory=$True)]
    [String] $ZoneID,

    [Parameter(Mandatory=$True)]
    [String] $DNSID
    )

    $Body = @{
        type = "A"
        name = "$NewDomain"
        content = "$IPAddress"
        proxied = $true
    }

    $JSONData = $Body | ConvertTo-Json
    $JSONResult = invoke-restmethod  -method PUT -uri $BaseURI"/$($ZoneID)/dns_records/$($DNSID)"  -ContentType "application/json"  -Headers $Headers -Body $JSONData
    return $JSONResult.success
}

#####################
## Start work here ##
#####################
##

## Populate array with the domain names and the redirections (CSV has a header line "DomainName,RedirectURL") - don't forget to change the path to the CSV!!!

## Loop through each array line
foreach ($Domain in $DomainList) {

  ## Populate the variables to be passed
  $NewDomain= $Domain.DomainName
  #RedirectURL = $Domain.RedirectURL
  $ZoneID = GetDZid($NewDomain)
  if (!$ZoneID) { #If there isn't a Zone ID - the domain probably needs to be added
    echo "Domain: $NewDomain does not yet exist. Addding.`r"
    $AddZoneResult = AddZone($NewDomain)

    $overview = ($AddZoneResult | ConvertFrom-Json)

    if ($overview.success -eq "True")
    {
      $ZoneID=[string]($overview.result)
    } else {
      $ZoneID = ""
      echo $overview.errors.message`r
    }
    if ($ZoneID -ne "") {
      $allrecords = GetDNSZones($ZoneID)    #Have DNS records been added? No? Then add some.
      if ( !$allrecords.result.id ) { #If there's no id in the results, there's not DNS records
        echo "Domain: $NewDomain has no DNS records`r"
        $addipaddress = ADDIPAddress($ZoneID)
        echo $addipaddress`r
      }
      ## Call the function to add the permanent redirection rule to the newly created zone
      $Result=AddRedirection -New_Domain $NewDomain -Zone_ID $ZoneID -ForwardingURL $RedirectURL
      #echo $Result
    }

  } else {
    echo "Domain: $NewDomain exists with ID $ZoneID`r"
    ## Here we can check if there's actuallly DNS records for the domain!!!
    $allrecords = GetDNSZones($ZoneID)
    if ( !$allrecords.result.id ) { #If there's no id in the results, there's not DNS records
      echo "Domain: $NewDomain has no DNS records. Adding.`r"
      $addipaddress = ADDIPAddress($ZoneID)
      echo $addipaddress`r
    } else { #DNS Records exist. Check the A record.
      #echo $allrecords.result`r
      foreach ($rec in $allrecords.result) { #There's likely a neater way to do this. Cycle through each record in the returned DNS entries
        if ( $rec.type -eq "A") { #Is the record type an 'A' record?  (this could become a variable for later)
          if ($rec.name -eq $NewDomain) { #Is the A record for the domain itself?
            $recontent = $rec.content
            $recproxied = $rec.proxied
            if (!$recproxied) {
              echo "Changing Proxy`n"
              $DNSID = $rec.id
              ChangeProxy $Zoneid $DNSID
            }
          }
        }
      }
    }
  }
}
## Call the function to create the new Zone in the Cloudflare Account and the new Zone ID is returned if successful
##  THE END!!  ##
