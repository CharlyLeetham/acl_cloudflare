## Cloudflare SiteStatus
# V1.0 By Charly Dwyer (20220302)

## Quick and Dirty PS Shell Script to find out which domains still need activation on CloudFlare.

## Change the following 3 values and populate with CloudFlare information known
##
## CFAccountID - open any site in the Account and it will show on the Overview page
## CFDomainEmail - what you use to login to Cloudflare
## CFAuthKey - Global API Key

$CFAccountID=""
$CFDomainEmail=""
$CFAuthKey=""

$BaseURI="https://api.cloudflare.com/client/v4/zones"
$HeaderEmail = "X-Auth-Email: "+$CFDomainEmail
$HeaderAuthKey = "X-Auth-Key: "+$CFAuthKey

$Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]" #Set the Header string for the RestMethod / Curl call
$Headers.Add("X-Auth-Email", "$CFDomainEmail") #Set the Auth Email in the Headers of the call
$Headers.Add("X-Auth-Key", "$CFAuthKey") #Set the Auth Key in the Headers of the call

Function GetDNSZones { #Find the Zones for an existing domain
  Param(
    [Parameter(Mandatory=$False)]
    [String] $ZoneID)

    $allrecords=invoke-restmethod  -method get -uri $BaseURI"/?per_page=1000&order=type&direction=asc&match=all" -Headers $Headers
    return $allrecords
}

#####################
## Start work here ##
#####################
##

##Get All domains
    $allrecords = GetDNSZones #Get all the Zones on the login

    if ( $allrecords.result_info.count -gt 0) { # If there are zones, then do the following
      foreach ($ar in $allrecords.result) { # Cycle through the results
        if ($ar.account.id -eq $CFAccountID) { # If the account id is the id we're looking for then
          $arname = $ar.name  # Set the domain name
          $arstatus = $ar.status # Set the domain status
          echo "$arname - $arstatus"  #Tell us
        }
      }

    }

##  THE END!!  ##
