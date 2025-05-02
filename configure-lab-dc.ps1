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
Import-Module ActiveDirectory
try {
    New-ADOrganizationalUnit -Name "Servers" -Path "DC=ptc,DC=corp" -ProtectedFromAccidentalDeletion `$true -ErrorAction Stop
    "OU creation successful" | Out-File -FilePath C:\ConfigureDC.log -Append
}
catch {
    "Error creating OU: `$_" | Out-File -FilePath C:\ConfigureDC.log -Append
}
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - OU creation task completed" | Out-File -FilePath C:\ConfigureDC.log -Append
"@

$TaskScript | Out-File -FilePath "C:\CreateOU.ps1" -Encoding ASCII
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\CreateOU.ps1"
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "CreateOU" -Action $Action -Trigger $Trigger -Principal $Principal -Description "Create Servers OU after DC promotion" -ErrorAction SilentlyContinue

Write-Log "Scheduled task created. Rebooting VM."
Restart-Computer -Force