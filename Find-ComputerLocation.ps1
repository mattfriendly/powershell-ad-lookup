<#
.SYNOPSIS
    Enhanced script to cross-reference IP addresses against AD subnets (AD_Subnets.csv)
    and find the corresponding site, plus do optional AD lookups.

.DESCRIPTION
    1. Imports AD_Subnets.csv, which has columns: Subnet, SiteName, ...
    2. Converts each subnet (CIDR) to a numeric range for easy matching.
    3. Imports Computers.csv (ComputerFQDN, LastLoggedInUser, IpAddress).
    4. For each record, determines the AD site by comparing IP address to subnets.
    5. Optionally queries AD to confirm computer object details and user details.
    6. Outputs the consolidated result, which can be saved to CSV.

.NOTES
    Adjust domain controllers, credential usage, or advanced error handling
    as needed for your environment.

.PARAMETER ComputerCsvPath
    Path to the Computers.csv file.

.PARAMETER SubnetsCsvPath
    Path to the AD_Subnets.csv file.

.PARAMETER OutputCsvPath
    Where to store the final results (optional).

.EXAMPLE
    .\Find-ComputerLocation.ps1
#>

param(
    [string]$ComputerCsvPath = "C:\temp\Computers.csv",
    [string]$SubnetsCsvPath  = "C:\temp\AD_Subnets.csv",
    [string]$OutputCsvPath   = "C:\temp\FinalResults.csv"
)

################################################################################
# 1) HELPER FUNCTIONS
################################################################################

function ConvertTo-UInt32Ip {
    <#
    .SYNOPSIS
        Converts a dotted-decimal IPv4 address (e.g. "10.10.10.5") to a uint32 number.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
        [string]$IpAddress
    )
    $octets = $IpAddress.Split('.')
    return [uint32](($octets[0] -shl 24) -bor
                    ($octets[1] -shl 16) -bor
                    ($octets[2] -shl 8)  -bor
                     $octets[3])
}

function ConvertCidrToRange {
    <#
    .SYNOPSIS
        Converts a CIDR notation (e.g. "10.10.10.0/24") into a hashtable containing
        the Network (lowest IP) and Broadcast (highest IP) in uint32 form.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}\/\d{1,2}$')]
        [string]$Cidr
    )

    $parts  = $Cidr.Split('/')
    $netIp  = $parts[0]
    $prefix = [int]$parts[1]

    $netNum = ConvertTo-UInt32Ip -IpAddress $netIp
    $mask   = [uint32](0xFFFFFFFF -shl (32 - $prefix))

    # Network address (lowest IP in the subnet)
    $network   = $netNum -band $mask
    # Broadcast address (highest IP in the subnet)
    $broadcast = $network -bor ([uint32]~$mask)

    return @{
        Network   = $network
        Broadcast = $broadcast
        Prefix    = $prefix
    }
}

function Test-IpInRange {
    <#
    .SYNOPSIS
        Checks if a given IP numeric (uint32) is between the specified Network and Broadcast.
    #>
    param(
        [Parameter(Mandatory)] [uint32]$IpNum,
        [Parameter(Mandatory)] [uint32]$Network,
        [Parameter(Mandatory)] [uint32]$Broadcast
    )

    return ($IpNum -ge $Network -and $IpNum -le $Broadcast)
}

################################################################################
# 2) IMPORT AD_SUBNETS AND TRANSFORM
################################################################################

Write-Host "`n[Info] Importing AD Subnets from $SubnetsCsvPath"
$adSubnets = Import-Csv -Path $SubnetsCsvPath

# Convert each Subnet entry to numeric ranges
foreach ($row in $adSubnets) {
    # For example, $row.Subnet might be "10.10.10.0/24"
    if ($row.Subnet -match '/') {
        try {
            $range = ConvertCidrToRange -Cidr $row.Subnet
            $row | Add-Member -NotePropertyName 'NetworkNum'   -NotePropertyValue $range.Network
            $row | Add-Member -NotePropertyName 'BroadcastNum' -NotePropertyValue $range.Broadcast
        }
        catch {
            Write-Warning "Failed to parse subnet $($row.Subnet): $($_.Exception.Message)"
            $row | Add-Member -NotePropertyName 'NetworkNum'   -NotePropertyValue $null
            $row | Add-Member -NotePropertyName 'BroadcastNum' -NotePropertyValue $null
        }
    }
    else {
        # If the format isn't CIDR, you can skip or handle differently
        Write-Warning "Subnet $($row.Subnet) is not in CIDR format."
        $row | Add-Member -NotePropertyName 'NetworkNum'   -NotePropertyValue $null
        $row | Add-Member -NotePropertyName 'BroadcastNum' -NotePropertyValue $null
    }
}

################################################################################
# 3) IMPORT COMPUTERS.CSV AND PROCESS
################################################################################

Write-Host "`n[Info] Importing Computers from $ComputerCsvPath"
$computers = Import-Csv -Path $ComputerCsvPath

# Optional: Define domain controllers or domains to search
# You might have multiple domains. Adjust as needed.
$domainControllers = @("dc1.domainA.local","dc2.domainB.local")

# We'll build an array of final results
$results = @()

foreach ($entry in $computers) {
    $computerFQDN     = $entry.ComputerFQDN
    $lastLoggedInUser = $entry.LastLoggedInUser
    $ipAddress        = $entry.IpAddress

    Write-Host "`nProcessing: $computerFQDN  (User: $lastLoggedInUser, IP: $ipAddress)"

    # Default site name in case no matching subnet is found
    $siteName = "Unknown"

    # 3a) Find the AD site by IP (if valid IPv4)
    if ($ipAddress -and $ipAddress -match '^(\d{1,3}\.){3}\d{1,3}$') {
        $ipNum = ConvertTo-UInt32Ip -IpAddress $ipAddress
        foreach ($subnet in $adSubnets) {
            if ($subnet.NetworkNum -and $subnet.BroadcastNum) {
                # Check if IP falls in this subnet
                if (Test-IpInRange -IpNum $ipNum -Network $subnet.NetworkNum -Broadcast $subnet.BroadcastNum) {
                    $siteName = $subnet.SiteName
                    break
                }
            }
        }
    }

    # 3b) (Optional) Query AD for the computer object
    #    We try each domain controller or domain until we find a match.
    $adComputer = $null
    if ($computerFQDN) {
        $shortName = $computerFQDN.Split(".")[0]
        foreach ($dc in $domainControllers) {
            try {
                # Attempt exact FQDN match
                $adComputer = Get-ADComputer -Server $dc -Filter "DNSHostName -eq '$computerFQDN'" -Properties *
                if (-not $adComputer) {
                    # Fallback to short name
                    $adComputer = Get-ADComputer -Server $dc -Filter "Name -eq '$shortName'" -Properties *
                }
                if ($adComputer) {
                    Write-Host "  Found computer in domain: $($adComputer.DistinguishedName)"
                    break
                }
            } catch {
                Write-Warning "  Error querying DC $dc for $computerFQDN: $($_.Exception.Message)"
            }
        }
    }

    # Gather computer data if found
    $computerOU      = $null
    $operatingSystem = $null
    $lastLogonDate   = $null
    if ($adComputer) {
        $computerOU      = $adComputer.CanonicalName
        $operatingSystem = $adComputer.OperatingSystem
        $lastLogonDate   = $adComputer.LastLogonDate
    }

    # 3c) (Optional) Query AD for the last logged in user
    #     This logic assumes either UPN or DOMAIN\Username
    $adUser = $null
    if ($lastLoggedInUser) {
        # Parse if we have domain\username
        if ($lastLoggedInUser -match '\\') {
            $parts = $lastLoggedInUser.Split('\')
            $userDomain  = $parts[0]
            $userAccount = $parts[1]
            $candidate   = "$userDomain\$userAccount"
        }
        elseif ($lastLoggedInUser -match '@') {
            # user@domain.local
            $candidate = $lastLoggedInUser
        }
        else {
            # Just a username, no domain info
            $candidate = $lastLoggedInUser
        }

        # Attempt to find the user in AD. 
        # You might also need to loop through domain controllers if truly multi-domain.
        try {
            $adUser = Get-ADUser -Identity $candidate -Properties DisplayName, Department, EmailAddress -ErrorAction SilentlyContinue
            if ($adUser) {
                Write-Host "  Found user: $($adUser.SamAccountName)"
            }
            else {
                Write-Host "  No AD user found for: $($lastLoggedInUser)"
            }
        }
        catch {
            Write-Warning "  Error searching for user $lastLoggedInUser: $($_.Exception.Message)"
        }
    }

    # Build a result object
    $obj = [PSCustomObject]@{
        ComputerFQDN      = $computerFQDN
        IpAddress         = $ipAddress
        AD_Site           = $siteName
        ComputerOU        = $computerOU
        OperatingSystem   = $operatingSystem
        LastLogonDate     = $lastLogonDate
        LastLoggedInUser  = $lastLoggedInUser
        UserSamAccount    = $adUser?.SamAccountName
        UserDisplayName   = $adUser?.DisplayName
        UserDepartment    = $adUser?.Department
    }

    $results += $obj
}

################################################################################
# 4) OUTPUT THE RESULTS
################################################################################

Write-Host "`n[Info] Processing complete. Summary of results:"
$results | Format-Table -AutoSize

Write-Host "`n[Info] Exporting final results to $OutputCsvPath"
$results | Export-Csv -Path $OutputCsvPath -NoTypeInformation
Write-Host "[Info] Done."
