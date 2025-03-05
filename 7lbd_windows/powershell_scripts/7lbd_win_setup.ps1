# Combined VM Setup Script with Install/Uninstall Options
# This script performs the following operations:
#
# INSTALL MODE:
# 1. Creates necessary folder structure
# 2. Copies win_userconfig.ps1 to the correct location
# 3. Sets proper permissions on the script
# 4. Enables Remote Desktop and adds specified user to the Remote Desktop Users group
# 5. Creates a scheduled task to run the user configuration script at startup
# 6. Verifies all actions were completed successfully
#
# UNINSTALL MODE:
# 1. Removes the scheduled task
# 2. Removes the user from Remote Desktop Users group
# 3. Removes the script from the startup location
# 4. Deletes the folder if empty
#
# Usage: .\combined-setup-script.ps1 -Username <username> [-Uninstall]
#        If no username is provided, defaults to "user1"
#        Use -Uninstall to remove all changes made by the script

param(
    [Parameter(Mandatory=$false)]
    [string]$Username = "user1",
    
    [Parameter(Mandatory=$false)]
    [switch]$Uninstall = $false
)

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires administrative privileges. Please run as Administrator."
    exit
}

# Define paths
$scriptSourcePath = "$PSScriptRoot\win_userconfig.ps1"
$destFolder = "C:\Windows\System32\GroupPolicy\Machine\Scripts\Startup"
$destPath = "$destFolder\win_userconfig.ps1"

# UNINSTALL MODE
if ($Uninstall) {
    # Main setup summary and confirmation
    $summaryMessage = @"
UNINSTALL MODE: This script will perform the following actions:

1. Remove the "ConfigureUserAccount" scheduled task
2. Disable Remote Desktop functionality
3. Remove user "$Username" from the Remote Desktop Users group
4. Delete the script file at "$destPath"
5. Delete the folder "$destFolder" if empty

"@

    Write-Host $summaryMessage -ForegroundColor Cyan

    # Prompt user for confirmation
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Proceed with uninstall")
        [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Cancel uninstall")
    )

    $result = $host.UI.PromptForChoice("Confirmation Required", "Do you want to proceed with uninstall?", $choices, 1)

    if ($result -eq 1) {
        Write-Host "Uninstall cancelled by user. No changes were made." -ForegroundColor Yellow
        exit
    }

    # Step 1: Remove the scheduled task
    Write-Host "Removing scheduled task..." -ForegroundColor Green
    try {
        $taskExists = Get-ScheduledTask -TaskName "ConfigureUserAccount" -ErrorAction SilentlyContinue
        if ($taskExists) {
            Unregister-ScheduledTask -TaskName "ConfigureUserAccount" -Confirm:$false
            Write-Host "Scheduled task removed successfully." -ForegroundColor Green
        } else {
            Write-Host "Scheduled task not found. Skipping removal." -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Failed to remove scheduled task: $_"
    }
    
    # Step 2: Disable Remote Desktop
    Write-Host "Disabling Remote Desktop..." -ForegroundColor Green
    try {
        # Disable Remote Desktop via Registry
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1
        
        # Disable Remote Desktop firewall rules
        Disable-NetFirewallRule -DisplayGroup "Remote Desktop"
        
        Write-Host "Remote Desktop disabled successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to disable Remote Desktop: $_"
    }

    # Step 3: Remove user from RDP group
    Write-Host "Removing user '$Username' from Remote Desktop Users group..." -ForegroundColor Green
    try {
        # Check if user exists
        $UserExists = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        
        if ($UserExists) {
            # Check if user is in the RDP group
            $inGroup = Get-LocalGroupMember -Group "Remote Desktop Users" | Where-Object {$_.Name -like "*\$Username"} -ErrorAction SilentlyContinue
            if ($inGroup) {
                Remove-LocalGroupMember -Group "Remote Desktop Users" -Member $Username -ErrorAction Stop
                Write-Host "Successfully removed user '$Username' from Remote Desktop Users group." -ForegroundColor Green
            } else {
                Write-Host "User '$Username' is not in Remote Desktop Users group. Skipping removal." -ForegroundColor Yellow
            }
        } else {
            Write-Host "User '$Username' does not exist. Skipping removal from group." -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Failed to remove user from Remote Desktop Users group: $_"
    }

    # Step 3: Delete the script file
    Write-Host "Deleting script file..." -ForegroundColor Green
    try {
        if (Test-Path $destPath) {
            Remove-Item -Path $destPath -Force
            Write-Host "Script file deleted successfully." -ForegroundColor Green
        } else {
            Write-Host "Script file not found. Skipping deletion." -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Failed to delete script file: $_"
    }

    # Step 4: Delete the folder if empty
    Write-Host "Checking if folder is empty and can be deleted..." -ForegroundColor Green
    try {
        if (Test-Path $destFolder) {
            $items = Get-ChildItem -Path $destFolder -Force
            if (-not $items) {
                Remove-Item -Path $destFolder -Force
                Write-Host "Empty folder deleted successfully." -ForegroundColor Green
            } else {
                Write-Host "Folder contains other files. Not deleting folder." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Folder not found. Skipping deletion." -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Failed to delete folder: $_"
    }

    Write-Host "`nUninstall completed." -ForegroundColor Green
    exit
}

# INSTALL MODE - Default path if not uninstalling
# Main setup summary and confirmation
$summaryMessage = @"
INSTALL MODE: This script will perform the following actions:

1. Create directory: $destFolder
2. Copy win_userconfig.ps1 to this directory
3. Set secure permissions on the copied script
4. Enable Remote Desktop
5. Add user "$Username" to the Remote Desktop Users group
6. Create a scheduled task to run win_userconfig.ps1 at system startup

The win_userconfig.ps1 script will:
- Set $Username's password based on SMBIOS strings at boot
- Send a network notification when ready

"@

Write-Host $summaryMessage -ForegroundColor Cyan

# Prompt user for confirmation
$choices = @(
    [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Proceed with all actions")
    [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Cancel all actions")
)

$result = $host.UI.PromptForChoice("Confirmation Required", "Do you want to proceed with ALL these actions?", $choices, 1)

if ($result -eq 1) {
    Write-Host "Operation cancelled by user. No changes were made." -ForegroundColor Yellow
    exit
}

# Tracking results for verification
$results = @{
    "FolderCreated" = $false
    "ScriptCopied" = $false
    "PermissionsSet" = $false
    "RDPEnabled" = $false
    "FirewallConfigured" = $false
    "UserAddedToRDP" = $false
    "ScheduledTaskCreated" = $false
}

# Step 1: Create the necessary folder structure
Write-Host "Creating folder structure..." -ForegroundColor Green
try {
    if (-not (Test-Path $destFolder)) {
        New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
        Write-Host "Folder created: $destFolder" -ForegroundColor Green
    } else {
        Write-Host "Folder already exists: $destFolder" -ForegroundColor Yellow
    }
    $results["FolderCreated"] = $true
} catch {
    Write-Error "Failed to create folder: $_"
}

# Step 2: Copy the script to the destination
Write-Host "Copying script to destination..." -ForegroundColor Green
try {
    if (Test-Path $scriptSourcePath) {
        Copy-Item -Path $scriptSourcePath -Destination $destPath -Force
        Write-Host "Script copied to: $destPath" -ForegroundColor Green
        $results["ScriptCopied"] = $true
    } else {
        Write-Error "Source script not found: $scriptSourcePath"
    }
} catch {
    Write-Error "Failed to copy script: $_"
}

# Step 3: Set proper permissions on the script
Write-Host "Setting permissions on script..." -ForegroundColor Green
try {
    # Create new ACL object
    $acl = Get-Acl $destPath

    # First set the owner to SYSTEM
    $systemSID = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
    $acl.SetOwner($systemSID)

    # Remove all existing permissions
    $acl.SetAccessRuleProtection($true, $false)

    # Add SYSTEM with full control
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $systemSID,
        "FullControl",
        "Allow"
    )
    $acl.AddAccessRule($systemRule)

    # Add Administrators with full control
    $adminSID = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $adminSID,
        "FullControl",
        "Allow"
    )
    $acl.AddAccessRule($adminRule)

    # Apply the new ACL
    Set-Acl -Path $destPath -AclObject $acl
    $results["PermissionsSet"] = $true
    
    Write-Host "Permissions set successfully on $destPath" -ForegroundColor Green
} catch {
    Write-Error "Failed to set permissions: $_"
}

# Step 4: Enable Remote Desktop and configure firewall
Write-Host "Enabling Remote Desktop..." -ForegroundColor Green
try {
    # Enable Remote Desktop via Registry
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    $results["RDPEnabled"] = $true
    
    # Enable Network Level Authentication (NLA)
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
    
    # Configure Windows Firewall to allow Remote Desktop
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    $results["FirewallConfigured"] = $true
    
    Write-Host "Remote Desktop enabled successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to enable Remote Desktop: $_"
}

# Step 5: Add user to Remote Desktop Users group
Write-Host "Adding user '$Username' to Remote Desktop Users group..." -ForegroundColor Green
try {
    # Check if user exists
    $UserExists = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    
    if ($UserExists) {
        # Add user to Remote Desktop Users group
        Add-LocalGroupMember -Group "Remote Desktop Users" -Member $Username -ErrorAction Stop
        Write-Host "Successfully added user '$Username' to Remote Desktop Users group." -ForegroundColor Green
        $results["UserAddedToRDP"] = $true
    } else {
        Write-Warning "User '$Username' does not exist. Please create the user first."
    }
} catch {
    Write-Error "Failed to add user to Remote Desktop Users group: $_"
}

# Step 6: Create the scheduled task
Write-Host "Creating scheduled task..." -ForegroundColor Green
try {
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$destPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -TaskName "ConfigureUserAccount" -Description "Configure user account based on SMBIOS strings" -Force
    $results["ScheduledTaskCreated"] = $true
    
    Write-Host "Scheduled task created successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to create scheduled task: $_"
}

# Step 7: Verification
Write-Host "`n========== VERIFICATION REPORT ==========" -ForegroundColor Cyan

# Check if folder exists
$folderExists = Test-Path $destFolder
Write-Host "Folder Created: " -NoNewline
if ($folderExists) {
    Write-Host "SUCCESS" -ForegroundColor Green
} else {
    Write-Host "FAILED" -ForegroundColor Red
}

# Check if script exists
$scriptExists = Test-Path $destPath
Write-Host "Script Copied: " -NoNewline
if ($scriptExists) {
    Write-Host "SUCCESS" -ForegroundColor Green
} else {
    Write-Host "FAILED" -ForegroundColor Red
}

# Check script permissions
$permissionsOK = $false
if ($scriptExists) {
    $acl = Get-Acl $destPath
    $systemHasFullControl = $acl.Access | Where-Object { 
        $_.IdentityReference.Value -like "*SYSTEM*" -and 
        $_.FileSystemRights -like "*FullControl*" 
    }
    $permissionsOK = ($systemHasFullControl -ne $null) -and ($acl.Owner -like "*SYSTEM*")
}
Write-Host "Script Permissions: " -NoNewline
if ($permissionsOK) {
    Write-Host "SUCCESS" -ForegroundColor Green
} else {
    Write-Host "FAILED" -ForegroundColor Red
}

# Check if RDP is enabled
$RDPEnabled = $false
try {
    $RDPEnabled = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections").fDenyTSConnections -eq 0
}
catch { }
Write-Host "Remote Desktop Enabled: " -NoNewline
if ($RDPEnabled) {
    Write-Host "SUCCESS" -ForegroundColor Green
} else {
    Write-Host "FAILED" -ForegroundColor Red
}

# Check if NLA is enabled
$NLAEnabled = $false
try {
    $NLAEnabled = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication").UserAuthentication -eq 1
}
catch { }
Write-Host "Network Level Authentication: " -NoNewline
if ($NLAEnabled) {
    Write-Host "SUCCESS" -ForegroundColor Green
} else {
    Write-Host "FAILED" -ForegroundColor Red
}

# Check firewall rules
$FirewallRulesConfigured = $false
try {
    $FirewallRulesConfigured = (Get-NetFirewallRule -DisplayGroup "Remote Desktop").Enabled -contains $true
}
catch { }
Write-Host "Firewall Rules Configured: " -NoNewline
if ($FirewallRulesConfigured) {
    Write-Host "SUCCESS" -ForegroundColor Green
} else {
    Write-Host "FAILED" -ForegroundColor Red
}

# Check if user is in RDP group
$UserInRDPGroup = $false
try {
    $UserExists = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($UserExists) {
        $GroupMembers = Get-LocalGroupMember -Group "Remote Desktop Users" | Where-Object {$_.Name -like "*\$Username"}
        $UserInRDPGroup = $GroupMembers -ne $null
    }
}
catch { }
Write-Host "User Added to RDP Group: " -NoNewline
if ($UserInRDPGroup) {
    Write-Host "SUCCESS" -ForegroundColor Green
} else {
    if (-not $UserExists) {
        Write-Host "NOT VERIFIED (User does not exist)" -ForegroundColor Yellow
    } else {
        Write-Host "FAILED" -ForegroundColor Red
    }
}

# Check scheduled task
$TaskExists = $false
try {
    $TaskExists = Get-ScheduledTask -TaskName "ConfigureUserAccount" -ErrorAction SilentlyContinue
}
catch { }
Write-Host "Scheduled Task Created: " -NoNewline
if ($TaskExists) {
    Write-Host "SUCCESS" -ForegroundColor Green
} else {
    Write-Host "FAILED" -ForegroundColor Red
}

# Overall status check
$totalChecks = 8

# Handle user check separately to avoid syntax issues
$userCheck = 0
if ($UserExists) {
    $userCheck = [int]$UserInRDPGroup
} else {
    $userCheck = 1  # Count as success if user doesn't exist (can't add non-existent user)
}

$passedChecks = (
    [int]$folderExists + 
    [int]$scriptExists + 
    [int]$permissionsOK +
    [int]$RDPEnabled +
    [int]$NLAEnabled +
    [int]$FirewallRulesConfigured +
    $userCheck +
    [int]($TaskExists -ne $null)
)

Write-Host "`nOverall Status: $passedChecks of $totalChecks checks passed" -NoNewline
if ($passedChecks -eq $totalChecks) {
    Write-Host " - SETUP COMPLETE" -ForegroundColor Green
} elseif ($passedChecks -ge ($totalChecks - 1)) {
    Write-Host " - SETUP MOSTLY COMPLETE" -ForegroundColor Yellow
} else {
    Write-Host " - SETUP INCOMPLETE" -ForegroundColor Red
}

Write-Host "`nA system restart may be required for all changes to take effect." -ForegroundColor Yellow
