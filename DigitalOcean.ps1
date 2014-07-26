# 
# DigitalOcean API v2 - PowerShell
# ================================
# Uses version 2 of the DigitalOcean RESTful Web API
# https://developers.digitalocean.com/
#
# Author: Matt Smith (matt@matt40k.uk)
# Date: 07/2015
# Version 0.a
# License: GPL v2
#

# On Error - Stop
$ErrorActionPreference = "Stop"

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

#  Default settings for your new droplets
$defaultregion = "lon1"
$defaultsize = "512mb"
$defaultimage = "ubuntu-14-04-x64"
$defaultbackups = "false"
$defaultipv6 = "true"
$defaultprivate_networking = "false"

# You need to create the domain first in order to automatically create 
# the pointer records, but you must first create the domain which 
# requires you to set an IP address. To get around the chicken and egg 
# scenerio we set a temporary IP address and change it to the droplets
# IP address once it's created. The default is the local loopback 
# address - 127.0.0.1
$tempip = "127.0.0.1"

# DigitalOcean API URL
$url = "https://api.digitalocean.com/v2"

# URL where to download Putty \ PuttyGen
# Putty is a free Windows SSH client and PuttyGen is a SSH keygen
$putty_download_site = "http://the.earth.li/~sgtatham/putty/latest/x86"

#######################################################################
######                                                            #####
######             DON'T EDIT ANYTHING BELOW THIS LINE            #####
######                                                            #####
#######################################################################

if ($api_key -eq $null)
{
  Write-Host "ERROR: No API key set in api.txt file!" -foregroundcolor red
  break
}

$header = @{"Authorization"="Bearer " + $api_key;"Content-Type"="application/json"}


# List all the droplets on your DigitalOcean account
Function ListAllDroplets
{
  $r = Invoke-WebRequest -Uri $url/droplets -Method GET -Headers $header
  return $r.Content | ConvertFrom-Json
}

# List all the domains on your DigitalOcean account
Function ListAllDomains
{
  $r = Invoke-WebRequest -Uri $url/domains -Method GET -Headers $header
  return $r.Content | ConvertFrom-Json
}

# Lists all the DC regions
Function ListAllRegions
{
  $r = Invoke-WebRequest -Uri $url/regions -Method GET -Headers $header
  return $r.Content
}

# Lists all the OS images avalible
Function ListAllImages
{
  $r = Invoke-WebRequest -Uri $url/images -Method GET -Headers $header
  return $r.Content
}

# Lists all the server sizes (512mb \ 1gb \ 2gb etc)
Function ListAllSizes
{
  $r = Invoke-WebRequest -Uri $url/sizes -Method GET -Headers $header
  return $r.Content
}

# Creates a new domain in DNS on your DigitalOcean account
Function CreateDomain($content)
{
  $r = Invoke-WebRequest -Uri $url/domains -Method POST -Headers $header -Body $content
  return $r.Content | ConvertFrom-Json
}

# Creates a new droplet on your DigitalOcean account
Function CreateDroplet($settings)
{
  $r = Invoke-WebRequest -Uri $url/droplets -Method POST -Headers $header -Body $settings
  return $r.Content | ConvertFrom-Json
}

# Lists the IPs (both IPv4 and IPv6) of your droplet
Function GetIPAddress($id)
{
  $r = Invoke-WebRequest -Uri $url/droplets/$id -Method GET -Headers $header
  return $r.Content | ConvertFrom-Json  | select droplet
}

# List all the DNS records for the newly created domain
Function ListAllRecords
{
  $r = Invoke-WebRequest -Uri $url/domains/$newdomain/records -Method GET -Headers $header
  return $r.Content | ConvertFrom-Json
}

# Create a DNS record for the newly created domain
Function CreateRecord ($data)
{
  $r = Invoke-WebRequest -Uri $url/domains/$newdomain/records -Method POST -Headers $header -Body $data
  return $r.Content | ConvertFrom-Json
}

# Update DNS record for the newly created domain
Function UpdateRecord ($data, $recordid)
{
  $r = Invoke-WebRequest -Uri $url/domains/$newdomain/records/$recordid -Method PUT -Headers $header -Body $data
  return $r.Content | ConvertFrom-Json
}

# Creates a DNS MX record on your new domain
Function CreateMXRecord($priority, $address)
{
  $mxrecord = @{priority=$priority;data=$address;type="MX"} | ConvertTo-Json
  CreateRecord -data $mxrecord
}

# Creates a DNS SPF record on your new domain
Function CreateSPFRecord($spf)
{
  $spfrecord = @{name="@";data=$spf;type="TXT"} | ConvertTo-Json
  CreateRecord -data $spfrecord
}

# Creates a DNS CNAME record on your new domain
Function CreateCNameRecord($cname, $address)
{
  $cnamerecord = @{name=$cname;data=$address;type="CNAME"} | ConvertTo-Json
  CreateRecord -data $cnamerecord
}

# Lists all the SSH public keys on your DigitalOcean account
Function ListAllKeys
{
  $r = Invoke-WebRequest -Uri $url/account/keys -Method GET -Headers $header
  return $r.Content | ConvertFrom-Json
}

# Uploads the local SSH public key onto your DigitalOcean account
Function UploadSSHKey
{
  $sshrecord = @{name="PowerShell";public_key=$localkey} | ConvertTo-Json
  $r = Invoke-WebRequest -Uri $url/account/keys -Method POST -Headers $header -Body $sshrecord
  $sshresult = $r.Content | ConvertFrom-Json
  return $sshresult.ssh_key.fingerprint
}

# Checks if the local SSH public key is loaded onto your DigitalOcean account
Function CheckRemoteSSHKey
{
  $allkeys = ListAllKeys
  $keys = $allkeys.ssh_keys
  Write-Host "Number of remote ssh keys:" $keys.Count

  If ($keys.Count -gt 0)
  {
    foreach ($key in $keys)
    {
      $remoteKeyResult = $key.public_key
      if ($remoteKeyResult -eq $localkey)
      {
        return $key.fingerprint
      }
    }
  }
  return $null
}

# Checks if Putty and Puttygen is present if not downloads it.
Function DownloadPutty
{
  if (!(Test-Path $scriptpath\putty.exe))
  {
    Invoke-WebRequest $putty_download_site/putty.exe -OutFile $scriptpath\putty.exe
  }
  if (!(Test-Path $scriptpath\puttygen.exe))
  {
    Invoke-WebRequest $putty_download_site/puttygen.exe -OutFile $scriptpath\puttygen.exe
  }
}

# Runs PuttyGen so the user can generate a secure (public\private) SSH key 
Function RunPuttyGen
{
  DownloadPutty
  Start-Process $scriptpath\puttygen.exe -Wait
}

# Check if the local SSH key has been generated, otherwise run PuttyGen
Function CheckLocalSSHKey
{
  if ( (Test-Path $scriptpath\public) -and (Test-Path $scriptpath\private.ppk) )
  {
    Write-Host "Local SSH key found"
  }
  else
  {
    Write-Host "================================="-foregroundcolor red
    Write-Host "= No local SSH keys found!"-foregroundcolor red
    Write-Host "================================="-foregroundcolor red
    Write-Host ""
    Write-Host "Please create a public\private SSH key and re-run."
    Write-Host "Visit:  for more information."
    Write-Host ""

    # Run PuttyGen to generate a SSH key to use
    RunPuttyGen

    # Abort
    break
  }
}

# Generates a secure password
# - 24 characters long
# - upper and lower case alphanumeric
# - and at least 1 special character
Function GenPass
{
  $chars = [Char[]]"012@;:,.<>#STUV3789qr4LMNOIJKcdABP6ab0I-CDEO1*23uvwxyzbcdefstuCDQR(_+IJKLMabvwxA)yzEWXYZF=BGHef!£^ghijklmnop56N4TUV$%WXRSYZ5678klmnopqrs0abcdeFGHOTfghij1290123agPQRSLMNFGHIJK678EFGHPQ9defghij456UVWXYZ789klopqrst3mn45chi7LMNJKABCDOPQRjklmnopqrstuvwS89TUVWxyzXYZ012ABC012345DE3456789"
  $genpass = ($chars | Get-Random -Count 24) -join ""
  if
    (($genpass.Contains("@")) -or ($genpass.Contains(';'))-or ($genpass.Contains(':')) -or ($genpass.Contains(',')) -or ($genpass.Contains('.')) -or ($genpass.Contains('<')) -or ($genpass.Contains('>')) -or ($genpass.Contains('#')) -or ($genpass.Contains('-')) -or ($genpass.Contains('*')) -or ($genpass.Contains('(')) -or ($genpass.Contains('_')) -or ($genpass.Contains('+'))  -or ($genpass.Contains(')'))  -or ($genpass.Contains('='))  -or ($genpass.Contains('!'))  -or ($genpass.Contains('£'))  -or ($genpass.Contains('^')) -or ($genpass.Contains('$'))  -or ($genpass.Contains('%'))  -or ($genpass.Contains('"')))
  {
    return $genpass
  }
  else
  {
    Write-Host "Error"
    return GenPass
  }
}

# Connect over SSH to new droplet using putty
Function RunPutty ($build_script)
{
  $ipadd = $ipv4.ip_address
  $sshaddress = "root@" + $ipadd
  $usrsshkey = $scriptpath+"\private.ppk"
  $args = "-ssh", $sshaddress, "-i", $usrsshkey
  Start-Process $scriptpath\putty.exe -Wait -ArgumentList $args
}


# Creates a new droplet [entire process]
Function CreateNewDroplet
{
Clear-Host
Write-Host "Create new droplet"
Write-Host "=================="
Write-Host ""

##
#  Create domain
$newdomain = Read-Host 'Domain name'

# Check if domain not exists:
If ($domains.name -contains $newdomain)
{
  # Domain already exists, abort!
  Write-Host "Domain already exists!" -foregroundcolor white -backgroundcolor red
  break
}

#
# TODO
# Added menu select for changing Images, Regions and Sizes from default
#

$newdomainbody = @{name=$newdomain;ip_address=$tempip} | ConvertTo-Json
$createddomain = CreateDomain -content $newdomainbody

##
# Create droplet

# If empty set to default
$newregion = $defaultregion
$newsize = $defaultsize
$newimage = $defaultimage
$newbackups = $defaultbackups
$newipv6 = $defaultipv6
$newprivate_networking = $defaultprivate_networking

##
#  And actually create it
$newdropletbody = @{name=$newdomain;region=$newregion;size=$newsize;image=$newimage;backups=$newbackups;ipv6=$newipv6;private_networking=$newprivate_networking;ssh_keys=@($sshid)} | ConvertTo-Json
$createddroplet = CreateDroplet -settings $newdropletbody

# Get the return droplet id
$id = $createddroplet.droplet.id

Write-Host ""
Write-Host "=========================================="
Write-Host ""
Write-Host "  droplet - id: " $id
Write-Host "  please wait while the droplet is build..."
Start-Sleep -s 30
Write-Host ""

# Get the IP address for the newly created droplet
$ip = GetIPAddress($id)

# Get IPv4 address
foreach ($ipv4 in $ip.droplet.networks.v4)
{
  Write-Host " IPv4 address: " $ipv4.ip_address
}

# Get IPv6 address
foreach ($ipv6 in $ip.droplet.networks.v6)
{
  Write-Host " IPv6 address: " $ipv6.ip_address
}

$records = ListAllRecords

foreach ($record in $records.domain_records)
{
  if ($record.type -Match "A")
  {
    $recordid = $record.id
  }
}

##
# Update IPv4 record with new droplet IP from the tempip (default: 127.0.0.1)
$newipv4record = @{data=$ipv4.ip_address} | ConvertTo-Json
UpdateRecord -data $newipv4record -recordid $recordid

##
# Create IPv6 record with new droplet IP
$newipv6record = @{name="@";data=$ipv6.ip_address;type="AAAA"} | ConvertTo-Json
CreateRecord -data $newipv6record

##
# Create default aliases (www, blog, secure)
$address = $newdomain + "."
CreateCNameRecord -cname "www" -address $address
CreateCNameRecord -cname "blog" -address $address
CreateCNameRecord -cname "secure" -address $address


####
#  
# Config mail settings
#
###

###############################################
# Rackspace Mail
###############################################
# Create MX records
CreateMXRecord -address "mx1.emailsrvr.com." -priority 10
CreateMXRecord -address "mx2.emailsrvr.com." -priority 20
# Create SPF TXT record
CreateSPFRecord -spf "v=spf1 include:emailsrvr.com ~all"
# Create CNAME record
CreateCNameRecord -cname "mail" -address "apps.rackspace.com."


####
#
# Run build script on new droplet
#
####

Write-Host "  please wait while the droplet starts up..."
Start-Sleep -s 120
RunPutty

}

#######################################################################
#
Function ConnectToDroplet
{
  Clear-Host
  Write-Host "Connect to an existing droplet"
  Write-Host "=============================="
  [int]$xMenuChoiceA = 0
  while ( $xMenuChoiceA -lt 1 -or $xMenuChoiceA -gt $droplets.Count ){
    for($counter=0;$counter -lt $droplets.Length;$counter++)
    {
      $dropno = $counter + 1
      Write-host $dropno - $droplets[$counter].name
    }
    [Int]$xMenuChoiceA = read-host "Connect to" 
  }
  $usrdropnets = $droplets[$xMenuChoiceA -1].networks
  foreach ($usrdropnet in $usrdropnets)
  {
    $ipv4 = $usrdropnet.v4
  }
  RunPutty
}

#######################################################################
#######################################################################

Write-Host ""
Write-Host "DigitalOcean API v2 - PowerShell"
Write-Host "================================"

# Check to see if we have a local SSH key (public \ private)
CheckLocalSSHKey

# Read the public SSH key
$localkey = $null
$localkeylines = Get-Content $scriptpath\public |?{ $_ -notmatch 'BEGIN SSH2 PUBLIC KEY' } |?{ $_ -notmatch 'Comment: ' } |?{ $_ -notmatch 'END SSH2 PUBLIC KEY' }
foreach ($keyline in $localkeylines)
{
  $localkey = $localkey + $keyline
}
$localkey = "ssh-rsa " + $localkey + " PowerShell"

#break
# Read what public SSH keys we have with DigitalOcean
$sshid = CheckRemoteSSHKey


If ($sshid -eq $null) {
  # Local Public SSH key not on DigitalOcean, lets upload it
  Write-Host "Adding local SSH public key to your DigitalOcean account"
  $sshid = UploadSSHKey
}

Write-Host "Using SSH key: PowerShell - Fingerprint: "$sshid

Write-Host ""
Write-Host "Account status"
Write-Host "=============="
Write-Host ""


##
#  Images
$images = ListAllImages
#Write-Host $images

##
#  Regions
$regions = ListAllRegions
#Write-Host $regions

##
#  Sizes
$sizes = ListAllSizes
#Write-Host $sizes


##
#  Droplets
$alldroplets = ListAllDroplets
$droplets = $alldroplets.droplets
Write-Host "Number of droplets:" $droplets.Count


##
#  Domains
$alldomains = ListAllDomains
$domains = $alldomains.domains

Write-Host "Number of domains:" $domains.Count

If ($domains.Count -gt 0)
{
  Write-Output $domains
}

If ($droplets.Count -gt 0)
{

  [int]$xMenuChoiceA = 0
  while ( $xMenuChoiceA -lt 1 -or $xMenuChoiceA -gt 4 ){
    Write-host "1. Create a new droplet"
    Write-host "2. Connect to an existing droplet"
    [Int]$xMenuChoiceA = read-host "What would you like to do?" }
    Switch( $xMenuChoiceA ){
    1 {
      # 1. Create a new droplet
      CreateNewDroplet
    }

    2 {
      # 2. Connect to an existing droplet
      ConnectToDroplet
    }
  }
}
else
{
  # No droplets created, let's create one!
  CreateNewDroplet
}