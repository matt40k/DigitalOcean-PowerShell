# DigitalOcean API for Cloud Firewall

# The scriptpath is the path for storing files and settings such as 
# your API key. The default path is the same directory as the script.
$scriptpath = Split-Path $MyInvocation.MyCommand.Path
# Uncomment if you want to use your my documents folder
#$scriptpath = ([environment]::getfolderpath("mydocuments"))

# Reads api.txt file for the API key
Function ReadAPIKey
{ 
  if (Test-Path $scriptpath\api.txt)
  {
    return Get-Content $scriptpath\api.txt
  }
  else
  {
    $ignore = New-Item $scriptpath\api.txt -type file
    Write-Host "ERROR: API is missing from api.txt file!" -foregroundcolor red
    break
  }
}

# Your API key is read from a separate text file called api.txt
# This file should only contain your API key
$api_key = ReadAPIKey 
#$api_key = {{ THIS IS MY PRIVATE DIGITALOCEAN API KEY HARDCODE IN }}


if ($api_key -eq $null)
{
  Write-Host "ERROR: No API key set in api.txt file!" -foregroundcolor red
  break
}

$header = @{"Authorization"="Bearer " + $api_key;"Content-Type"="application/json"}

# List all the Cloud Firewalls on your DigitalOcean account
Function ListAllFirewalls
{
  $r = Invoke-WebRequest -Uri $url/firewalls  -Method GET -Headers $header
  return $r.Content | ConvertFrom-Json
}

# Create "Web Server via CloudFlare" Cloud Firewall
Function CreateWebViaCloudFlareFirewall
{
  $r = ListAllFirewalls
  if ($r.firewalls.Count -eq 0)
  {
    $content = @"
{
  "name": "firewall",
  "inbound_rules": [
    {
      "protocol": "tcp",
      "ports": 22,
      "sources": {
        "addresses": [
          "$myIp/32"
        ]
      }
    }
  ],
  "outbound_rules": [
    {
      "protocol": "tcp",
      "ports": "80",
      "destinations": {
        "addresses": [
          "0.0.0.0/0",
          "::/0"
        ]
      }
    }
  ],
  "droplet_ids": null,
  "tags": null
}
"@
    $r = Invoke-WebRequest -Uri $url/firewalls -Method POST -Headers $header -Body $content
    return $r.Content | ConvertFrom-Json            
  }
}


# Get your IP
Function GetMyIp
{
    #$myIpUri = 'http://v6.ipv6-test.com/api/myip.php'
    #$myIpUri = 'http://v4.ipv6-test.com/api/myip.php'
    $myIpUri = 'http://v4v6.ipv6-test.com/api/myip.php'
    $r = Invoke-WebRequest -Uri $myIpUri
    return $r.Content
}

# CloudFlare IPs
Function GetCloudFlareIps
{
    $cf_ip4Uri = 'https://www.cloudflare.com/ips-v4'
    $cf_ip6Uri = 'https://www.cloudflare.com/ips-v6'
    $cf_r4 = Invoke-WebRequest -Uri $cf_ip4Uri
    $cf_ip4 = $cf_r4.Content
    $cf_r6 = Invoke-WebRequest -Uri $cf_ip6Uri
    $cf_ip6 = $cf_r6.Content
    $cf_iplist = $cf_ip4 + $cf_ip6
    return $cf_iplist -replace "`n",","
}

$cf_ips = GetCloudFlareIps
Write-Host $cf_ips

#$myIP = GetMyIp
#Write-Host $myIP

#CreateWebViaCloudFlareFirewall
