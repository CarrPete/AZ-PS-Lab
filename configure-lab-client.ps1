param (
    [string]$DomainName = "ptc.corp",
    [string]$AdminUsername,
    [string]$AdminPassword,
    [string]$ClientVmName = "Client01"
)

# Secure credential creation
$SecurePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($AdminUsername, $SecurePassword)

# Logging setup
$LogFile = "C:\ConfigureClient.log"
function Write-Log {
    param ($Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFile -Append
}

# Determine if running on Client
$ComputerName = (Get-WmiObject Win32_ComputerSystem).Name
if ($ComputerName -ne $ClientVmName) {
    Write-Log "This script is intended for Client01. Exiting."
    exit 1
}

Write-Log "Starting configuration for Client01"

# Configure DNS to point to DC
Write-Log "Configuring DNS"
try {
    Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("10.0.1.4") -ErrorAction Stop
    Write-Log "DNS configured successfully"
}
catch {
    Write-Log "Error configuring DNS: $_"
    exit 1
}

# Join the domain
Write-Log "Joining domain"
try {
    Add-Computer -DomainName $DomainName -Credential $Credential -OUPath "OU=Servers,DC=ptc,DC=corp" -Restart -ErrorAction Stop
    Write-Log "Domain join initiated"
}
catch {
    Write-Log "Error joining domain: $_"
    exit 1
}