# Script to set user1's password based on SMBIOS string 
# Ensure we're running with administrative privileges 
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run this script as Administrator"
    exit 1
}

try {
    # Get SMBIOS strings and look for password
    $passwordString = (Get-WmiObject -Class "Win32_ComputerSystem").OEMStringArray | Where-Object { $_ -match "^password=" }
    if (-not $passwordString) {
        Write-Host "No password string found in SMBIOS. Exiting."
        exit 0
    }

    # Extract password and update user 
    if ($passwordString -match "^password=(.+)") {
        $newPassword = $matches[1]
        $securePassword = ConvertTo-SecureString $newPassword -AsPlainText -Force
        Set-LocalUser -Name "user1" -Password $securePassword
        Write-Host "Successfully updated password for user1"
        
        # Send network notification to after.sh.erb
        # Notification alerts OOD that user is ready to log in
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect("169.254.100.2", 54321)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.WriteLine("READY")
        $writer.Flush()
        $client.Close()
    }
} catch {
    Write-Error "Failed to update password: $_"
    exit 1
} finally {
    # Clear sensitive data
    if ($null -ne $newPassword) {
        $newPassword = $null
    }
    [System.GC]::Collect()
}
