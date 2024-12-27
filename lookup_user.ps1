# import the names
$csvPath = "C:\temp\email_lookup.csv"
$csvData = Import-Csv -Path $csvPath

# Loop through each name in the CSV
foreach ($entry in $csvData) {
    $fullName = $entry.Name  # Assuming the CSV has a column named "Name" with full name (First Last)
    if (-not $fullName) {
        Write-Host "Warning: No name found in the entry."
        continue
    }

    # Split the full name into first name and last name
    $nameParts = $fullName -split "\s+"  # Split by one or more spaces

    # Check if the name was split correctly
    if ($nameParts.Count -eq 1) {
        $firstName = $nameParts[0]
        $lastName = ""
    } elseif ($nameParts.Count -eq 2) {
        $firstName = $nameParts[0]
        $lastName = $nameParts[1]
    } else {
        $firstName = $nameParts[0]
        $lastName = $nameParts[1..($nameParts.Count - 1)] -join " "
    }

    # Trim any leading or trailing whitespace
    $firstName = $firstName.Trim()
    $lastName = $lastName.Trim()

    # Log the processed name components
    Write-Host "Processing name: $fullName"
    Write-Host "First Name: '$firstName', Last Name: '$lastName'"

    # Ensure the filter query is not malformed (empty names will cause issues)
    if (-not $firstName -or -not $lastName) {
        Write-Host "Warning: First name or last name is missing. Skipping this entry."
        continue
    }

    # Use Get-ADUser to search for users whose GivenName and Surname match the first and last names
    try {
        Write-Host "Querying AD with GivenName -like '*$firstName*' and Surname -like '*$lastName*'"

        # First, check for exact matches (Using -eq for exact matching)
        $user = Get-ADUser -Filter "GivenName -eq '$firstName' -and Surname -eq '$lastName'" -Properties EmailAddress, GivenName, Surname, Department, LastLogonDate

        if (-not $user) {
            # If exact match doesn't work, fall back to partial matching
            Write-Host "No exact match found. Falling back to partial match..."
            $user = Get-ADUser -Filter "GivenName -like '*$firstName*' -and Surname -like '*$lastName*'" -Properties EmailAddress, GivenName, Surname, Department, LastLogonDate
        }

        # Log the user found (or not)
        if ($user) {
            Write-Host "User found: $($user.SamAccountName)"
            
            # If the LastLogonDate exists, show it
            $lastLogonComputer = $user.LastLogonDate
            if ($lastLogonComputer) {
                Write-Host "User last logged on: $lastLogonComputer"
                # For this example, we're just outputting the LastLogonDate
                # If you need to track the actual computer, you might need to adjust the logic.
                # Example: You could query for logon events in Event Viewer or use LogonWorkstation if it's set.
                $adSite = "Site information is unavailable"
                Write-Host "AD Site for this user: $adSite"
            } else {
                $adSite = "Not Available"
                Write-Host "No logon info available, AD Site: $adSite"
            }

            # Output or process the desired user attributes, including AD Site if possible
            Write-Host "User: $($user.SamAccountName)"
            Write-Host "Email: $($user.EmailAddress)"
            Write-Host "Given Name: $($user.GivenName)"
            Write-Host "Surname: $($user.Surname)"
            Write-Host "Department: $($user.Department)"
            Write-Host "Last Logon: $($user.LastLogonDate)"
            Write-Host "AD Site: $adSite"
            Write-Host "----------"
        } else {
            Write-Host "No matching user found for: $fullName"
        }
    } catch {
        # Log the full error object to understand what went wrong
        Write-Host "Error processing user $fullName. Error details: $($_.Exception.Message)"
        Write-Host "Full error object: $($_ | Format-List -Force)"
    }
}
