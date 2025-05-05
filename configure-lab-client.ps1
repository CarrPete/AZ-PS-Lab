param (
    [string]$DomainName = "ptc.corp",
    [string]$AdminUsername,
    [string]$AdminPassword,
    [string]$ClientVmName = "Client01"
)

# Logging setup
$LogFile = "C:\ConfigureClient.log"
function Write-Log {
    param ($Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFile -Append
}

# Initial log entry
Write-Log "Script started on Client01"

# Secure credential creation
Write-Log "Creating credentials for domain join"
try {
    $DomainQualifiedUsername = "ptc\$AdminUsername"
    $SecurePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential ($DomainQualifiedUsername, $SecurePassword)
    Write-Log "Credentials created for user: $DomainQualifiedUsername"
}
catch {
    Write-Log "Error creating credentials: $_"
    exit 1
}

# Determine if running on Client
$ComputerName = (Get-WmiObject Win32_ComputerSystem).Name
if ($ComputerName -ne $ClientVmName) {
    Write-Log "This script is intended for Client01. Exiting."
    exit 1
}

Write-Log "Starting configuration for Client01"

# Get network interface
Write-Log "Retrieving network interface..."
try {
    $Interface = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if (-not $Interface) {
        Write-Log "No active network interface found."
        exit 1
    }
    $InterfaceAlias = $Interface.Name
    Write-Log "Found network interface: $InterfaceAlias"
}
catch {
    Write-Log "Error retrieving network interface: $_"
    exit 1
}

# Configure DNS to point to DC
Write-Log "Configuring DNS to 10.0.1.4"
try {
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses ("10.0.1.4") -ErrorAction Stop
    Write-Log "DNS configured successfully"
}
catch {
    Write-Log "Error configuring DNS: $_"
    exit 1
}

# Verify DNS resolution
Write-Log "Verifying DNS resolution for $DomainName"
try {
    $DnsResult = Resolve-DnsName -Name $DomainName -ErrorAction Stop
    Write-Log "DNS resolution successful: $($DnsResult.Name)"
}
catch {
    Write-Log "Error resolving DNS: $_"
    exit 1
}

# Join the domain
Write-Log "Joining domain $DomainName"
try {
    Add-Computer -DomainName $DomainName -Credential $Credential -OUPath "OU=Servers,DC=ptc,DC=corp" -Restart -ErrorAction Stop
    Write-Log "Domain join initiated"
}
catch {
    Write-Log "Error joining domain: $_"
    exit 1
}
