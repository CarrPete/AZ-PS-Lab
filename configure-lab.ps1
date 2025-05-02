param (
    [string]$DomainName = "ptc.corp",
    [string]$AdminUsername,
    [string]$AdminPassword,
    [string]$DCVmName = "DC01",
    [string]$ClientVmName = "Client01"
)

# Secure credential creation
$SecurePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($AdminUsername, $SecurePassword)

# Determine if running on DC or Client VM
$ComputerName = (Get-WmiObject Win32_ComputerSystem).Name

if ($ComputerName -eq $DCVmName) {
    # Install AD DS role
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

    # Promote to Domain Controller
    Install-ADDSForest `
        -DomainName $DomainName `
        -InstallDns `
        -DomainMode WinThreshold `
        -ForestMode WinThreshold `
        -DatabasePath "C:\Windows\NTDS" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$false `
        -Force:$true `
        -SafeModeAdministratorPassword $SecurePassword

    # Create OU
    New-ADOrganizationalUnit -Name "Servers" -Path "DC=ptc,DC=corp" -ProtectedFromAccidentalDeletion $true
}
elseif ($ComputerName -eq $ClientVmName) {
    # Configure DNS to point to DC
    Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("10.0.1.4")

    # Join the domain
    Add-Computer -DomainName $DomainName -Credential $Credential -OUPath "OU=Servers,DC=ptc,DC=corp" -Restart
}
