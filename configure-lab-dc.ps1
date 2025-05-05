param (
    [string]$DomainName = "ptc.corp",
    [string]$AdminUsername,
    [string]$AdminPassword,
    [string]$DCVmName = "DC01"
)

# Secure credential creation
$SecurePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($AdminUsername, $SecurePassword)

# Logging setup
$LogFile = "C:\ConfigureDC.log"
function Write-Log {
    param ($Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFile -Append
}

# Determine if running on DC
$ComputerName = (Get-WmiObject Win32_ComputerSystem).Name
if ($ComputerName -ne $DCVmName) {
    Write-Log "This script is intended for DC01. Exiting."
    exit 1
}

Write-Log "Starting configuration for DC01"

# Install AD DS role
Write-Log "Installing AD DS role"
try {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
    Write-Log "AD DS role installed successfully"
}
catch {
    Write-Log "Error installing AD DS role: $_"
    exit 1
}

# Promote to Domain Controller
Write-Log "Promoting to Domain Controller"
try {
    Install-ADDSForest `
        -DomainName $DomainName `
        -InstallDns `
        -DomainMode WinThreshold `
        -ForestMode WinThreshold `
        -DatabasePath "C:\Windows\NTDS" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$true `
        -Force:$true `
        -SafeModeAdministratorPassword $SecurePassword `
        -ErrorAction Stop
    Write-Log "Domain Controller promotion completed"
}
catch {
    Write-Log "Error promoting to Domain Controller: $_"
    exit 1
}

# Create a scheduled task to run OU creation after reboot
Write-Log "Creating scheduled task for OU creation"
$TaskScript = @"
Start-Sleep -Seconds 60
`$LogFile = "C:\ConfigureDC.log"
function Write-Log {
    param (`$Message)
    `$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "`$Timestamp - `$Message" | Out-File -FilePath `$LogFile -Append
}
`$MaxRetries = 5
`$RetryCount = 0
`$Success = `$false
while (-not `$Success -and `$RetryCount -lt `$MaxRetries) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Log "Attempting OU creation (Attempt `$($RetryCount + 1))"
        New-ADOrganizationalUnit -Name "Servers" -Path "DC=ptc,DC=corp" -ProtectedFromAccidentalDeletion `$true -ErrorAction Stop
        Write-Log "OU creation successful"
        `$Success = `$true
    }
    catch {
        Write-Log "Error creating OU: `$_"
        `$RetryCount++
        if (`$RetryCount -lt `$MaxRetries) {
            Write-Log "Retrying in 30 seconds..."
            Start-Sleep -Seconds 30
        }
    }
}
if (-not `$Success) {
    Write-Log "Failed to create OU after `$MaxRetries attempts"
}
Write-Log "OU creation task completed"
"@

$TaskScript | Out-File -FilePath "C:\CreateOU.ps1" -Encoding ASCII
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\CreateOU.ps1"
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "CreateOU" -Action $Action -Trigger $Trigger -Principal $Principal -Description "Create Servers OU after DC promotion" -ErrorAction SilentlyContinue

Write-Log "Scheduled task created. Rebooting VM."
Restart-Computer -Force
