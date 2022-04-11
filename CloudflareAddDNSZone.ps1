## Cloudflare Bulk domain importer
# V1.0 by Grahame Petch (20220202)
# V1.1 by Charly Dwyer (20220411)

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


Function GetDZid{ #Called to find the ZoneID of the domain we're working with.

  Param(
    [Parameter(Mandatory=$True)]
    [String] $zone)

  #Thanks to https://www.powershellgallery.com/packages/Posh-ACME/2.0/Content/DnsPlugins%5CCloudflare.ps1 for base code for this.
  $zoneid=invoke-restmethod  -method get -uri "https://api.cloudflare.com/client/v4/zones/?per_page=1000&order=type&direction=asc" -Headers $Headers #make the request
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

    $allrecords=invoke-restmethod  -method get -uri "https://api.cloudflare.com/client/v4/zones/$($ZoneID)/dns_records?per_page=1000&order=type&direction=asc&match=all" -Headers $Headers
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
        proxied = $True
    }

    $JSONData = $Body | ConvertTo-Json
    $JSONResult = invoke-restmethod  -method Post -uri "https://api.cloudflare.com/client/v4/zones/$($ZoneID)/dns_records"  -ContentType "application/json"  -Headers $Headers -Body $jsondata
    return $JSONResult.success
}

Function ADDCName {

  Param(
    [Parameter(Mandatory=$True)]
    [String] $ZoneID)

    $Body = @{
        type = "CNAME"
        name = "www.$NewDomain"
        content = "$NewDomain"
        proxied = $True
    }

    $JSONData = $Body | ConvertTo-Json
    $JSONResult = invoke-restmethod  -method Post -uri "https://api.cloudflare.com/client/v4/zones/$($ZoneID)/dns_records"  -ContentType "application/json"  -Headers $Headers -Body $jsondata
    return $JSONResult.success
}




Function ChangeProxy {

  Param(
    [Parameter(Mandatory=$True)]
    [String] $ZoneID,

    [Parameter(Mandatory=$True)]
    [String] $DNSID,

    [Parameter(Mandatory=$True)]
    [String] $rectype

    )

    if ( $rectype -eq "A" ) {
      $Body = @{
          type = "A"
          name = "$NewDomain"
          content = "$IPAddress"
          proxied = $true
      }
    } elseif ( $rectype -eq "CNAME" ) {
      $Body = @{
          type = "CNAME"
          name = "www.$NewDomain"
          content = "$NewDomain"
          proxied = $true
      }
    }

    $JSONData = $Body | ConvertTo-Json
    $JSONResult = invoke-restmethod  -method PUT -uri "https://api.cloudflare.com/client/v4/zones/$($ZoneID)/dns_records/$($DNSID)"  -ContentType "application/json"  -Headers $Headers -Body $JSONData
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

    ## Check for DNS Zone and add records.
    $allrecords = GetDNSZones($ZoneID)    #Have DNS records been added? No? Then add some.
    if ( !$allrecords.result.id ) { #If there's no id in the results, there's not DNS records
      echo "Domain: $NewDomain has no DNS records`r"
      $addipaddress = ADDIPAddress($ZoneID)
      echo $addipaddress`r
      $addcname = ADDCName($ZoneID)
      echo $addcname`r
    } else { # There are zones already. Make sure there is a CNAME
      echo "Domain: $NewDomain has DNS records. Checking for A record and CName`r"
      echo $allrecords.result`r

      $rec = $allrecords.result #The main array so we can work.
      $ar = $allrecords.result #This gets filtered as we go through


      ## Check if the A Record exists
      switch ( ($ar.type -contains "A") -and ($ar.content -contains $IPAddress) -and ($ar.name -contains $NewDomain ) ) {
        false {
            ### The A record for the domain is missing. Or the IP address is wrong. ###
            echo "Domain: $NewDomain has no A record. Adding ...`r"
            $addipaddress = ADDIPAddress($ZoneID)
            echo "Added: "$addipaddress`r
        }

        true {
         break
        }
      }

      ## Check if the CName entry exists
      switch ( ($ar.type -contains "CNAME") -and ($ar.name -contains "www.$newDomain") ) {
        true {
          break
        }

        false {
          echo "Domain: $NewDomain has no CNAME record. Adding...`r"
          $addipaddress = ADDCName($ZoneID)
          echo "Added: "$addipaddress`r
        }
      }

      ## As a catchall, make sure proxy is turned on, just in case something went screwy
      switch ( ( ($ar.type -contains "A") -and ($ar.content -contains $IPAddress) ) -or ( ($ar.type -contains "CNAME") -and ($ar.name -contains $NewDomain) ) ) {
        ## Filtered for on A records that contain our IP address OR CNames that are on our main domain (not subdomains etc)
        true {
          foreach ( $a1 in $ar ) {
            switch ( ( $a1.proxiable ) -and ( !$a1.proxied ) ) {
              true {
                $a1name = $a1.name
                $a1type = $a1.type
                echo "Changing Proxy for $a1name ($a1type)`n"
                $DNSID = $a1.id
                $cp = ChangeProxy $ZoneID $DNSID $a1type
                echo $cp
              }

              false {
                break
              }
            }
          }

        }

        false { #No records need checking
          break
        }
      }
    }

  } else {
    echo "Domain: $NewDomain exists with ID $ZoneID`r"
    ## Here we can check if there's actuallly DNS records for the domain!!!
    $allrecords = GetDNSZones($ZoneID)
    $rec = $allrecords.result #The main array so we can work.
    $ar = $allrecords.result #This gets filtered as we go through

    ## Check if the A Record exists
    switch ( ($ar.type -contains "A") -and ($ar.content -contains $IPAddress) -and ($ar.name -contains $NewDomain ) ) {
      false {
          ### The A record for the domain is missing. Or the IP address is wrong. ###
          echo "Domain: $NewDomain has no A record`r"
          $addipaddress = ADDIPAddress($ZoneID)
          echo $addipaddress`r
      }

      true {
       break
      }
    }

    ## Check if the CName entry exists
    switch ( ($ar.type -contains "CNAME") -and ($ar.name -contains "www.$newDomain") ) {
      true {
        break
      }

      false {
        echo "Domain: $NewDomain has no CNAME record`r"
        $addipaddress = ADDCName($ZoneID)
        echo $addipaddress`r
      }
    }

    ## As a catchall, make sure proxy is turned on, just in case something went screwy
    switch ( ( ($ar.type -contains "A") -and ($ar.content -contains $IPAddress) ) -or ( ($ar.type -contains "CNAME") -and ($ar.name -contains $NewDomain) ) ) {
      ## Filtered for on A records that contain our IP address OR CNames that are on our main domain (not subdomains etc)
      true {
        foreach ( $a1 in $ar ) {
          switch ( ( $a1.proxiable ) -and ( !$a1.proxied ) ) {
            true {
              $a1name = $a1.name
              $a1type = $a1.type
              echo "Changing Proxy for $a1name ($a1type)`n"
              $DNSID = $a1.id
              $cp = ChangeProxy $ZoneID $DNSID $a1type
              echo $cp
            }

            false {
              break
            }
          }
        }

      }

      false { #No records need checking
        break
      }
    }
  }
}
## Call the function to create the new Zone in the Cloudflare Account and the new Zone ID is returned if successful
##  THE END!!  ##
