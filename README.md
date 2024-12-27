# Powershell AD Utilities – README

This repository contains three PowerShell scripts designed to work with an Active Directory (AD) environment. Each script handles a distinct task, yet they can be used together to provide a more comprehensive view of AD objects, subnets, and locations.

## 1. **lookup_user.ps1**
- **Purpose**: Looks up AD users by **name** (First and Last).
- **Key Functionality**:
  - Reads a CSV file (e.g., `email_lookup.csv`) containing user full names.
  - Splits each full name into first and last name, then queries AD for matching user accounts.
  - Displays user details (e.g., SamAccountName, Email, Department, LastLogonDate).

## 2. **get_subnets.ps1**
- **Purpose**: Exports the current AD replication subnets from **Sites & Services** to a CSV file (`AD_Subnets.csv`).
- **Key Functionality**:
  - Enumerates all Domain Controllers in the forest to gather site information.
  - Retrieves AD replication subnets and extracts their **SiteName**, **Location**, and other optional details.
  - Outputs a clean CSV of subnet-to-site mappings, which can be used by other scripts.

## 3. **Find-ComputerLocation.ps1**
- **Purpose**: Finds computer objects in AD, determines their **AD Site** by IP, and optionally retrieves user or system info.
- **Key Functionality**:
  - Reads a CSV file (`Computers.csv`) with `ComputerFQDN`, `LastLoggedInUser`, and `IpAddress`.
  - Cross-references IP addresses against the subnets exported by **get_subnets.ps1** to identify the AD Site.
  - (Optional) Looks up the computer object and user details in AD (can run in parallel to handle large datasets).

---

### How They Work Together

1. **get_subnets.ps1** creates an **`AD_Subnets.csv`** file containing each subnet and its corresponding **SiteName**.  
2. **Find-ComputerLocation.ps1** uses **`AD_Subnets.csv`** to match a computer’s IP address to the correct site and retrieve additional AD data.  
3. **lookup_user.ps1** is independent but complements this toolkit by finding detailed info about specific users.

---

**Note**:  
- These scripts assume you have appropriate permissions to query AD.  
- Adjust file paths, CSV column names, and filtering logic to match your environment.  

For any questions or more details, please check the scripts’ inline comments.
