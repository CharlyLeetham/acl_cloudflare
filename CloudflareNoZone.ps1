## Cloudflare Bulk domain importer and redirector script
# V1.0 by Grahame Petch (20220202)
# V1.1 By Charly Dwyer (20220302)
# V1.2 By Charly Dwyer (20220310)



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

$IPAddress = ""
$DomainList = import-csv pathtofile\filename

Function GetDZid{ #Called to find the ZoneID of the domain we're working with.

  #Thanks to https://www.powershellgallery.com/packages/Posh-ACME/2.0/Content/DnsPlugins%5CCloudflare.ps1 for base code for this.
  $zoneid=invoke-restmethod  -method get -uri "https://api.cloudflare.com/client/v4/zones/?per_page=1000&order=type&direction=asc" -Headers $Headers #make the request
  $allzones = $zoneid.result #Get all the zones in the results
  $totalzones = $zoneid.result_info.count #Get the total number of zones in the result
  return $zoneid
}

#####################
## Start work here ##
#####################
##

## Populate array with the domain names and the redirections (CSV has a header line "DomainName,RedirectURL") - don't forget to change the path to the CSV!!!

## Loop through each array line
$ZoneID = GetDZid
foreach ($Domain in $DomainList) {
  ## Populate the variables to be passed
  $NewDomain= $Domain.DomainName
  #RedirectURL = $Domain.RedirectURL
  $targetdomain = $ZoneID.result | Where-Object {$_.name -eq "$NewDomain"}  #Now the work begins. Select the domain we're looking for using the domainname.
  $targetdomainzid = $targetdomain.id
  if (!$targetdomainzid) { #If there isn't a Zone ID - the domain probably needs to be added
    echo "Domain: $NewDomain does not yet exist.`r"
  }
}
## Call the function to create the new Zone in the Cloudflare Account and the new Zone ID is returned if successful
##  THE END!!  ##
