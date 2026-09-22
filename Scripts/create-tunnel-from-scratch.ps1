# ============================================================
# create-tunnel-from-scratch.ps1
#
# Complete IPsec IKEv2 site-to-site tunnel setup from scratch.
# Run this on a fresh Windows Server 2019/2022.
# Covers everything: RRAS install, tunnel creation,
# traffic selectors, firewall rules, and verification.
#
# Before running:
#   Set-ExecutionPolicy RemoteSigned
#   $env:VPN_PSK = "your-psk-here"
#   Edit the CONFIGURATION section below
# ============================================================

#region CONFIGURATION — edit these values
$LocalIP            = "YOUR_SERVER_IP"         # This server's public IP
$PrimaryName        = "VPN-Primary"            # Primary tunnel name
$PrimaryGateway     = "REMOTE_GATEWAY_IP"      # Remote gateway IP
$PrimarySubnet      = "REMOTE_SUBNET/MASK"     # e.g. 10.1.0.0/24
$PrimaryRemoteStart = "REMOTE_SUBNET_START"    # e.g. 10.1.0.0
$PrimaryRemoteEnd   = "REMOTE_SUBNET_END"      # e.g. 10.1.0.255
$PrimaryP1Life      = 86400                    # Phase 1 lifetime (seconds)
$PrimaryP2Life      = 28800                    # Phase 2 lifetime (seconds)

$BackupName         = "VPN-Backup"             # Backup tunnel name
$BackupGateway      = "BACKUP_GATEWAY_IP"      # Backup gateway IP
$BackupSubnet       = "BACKUP_SUBNET/MASK"     # e.g. 10.2.0.1/32
$BackupRemoteStart  = "BACKUP_REMOTE_START"    # e.g. 10.2.0.1
$BackupRemoteEnd    = "BACKUP_REMOTE_END"      # e.g. 10.2.0.1
$BackupP1Life       = 28800
$BackupP2Life       = 28800

$P1Encryption       = "AES256"                 # Phase 1 encryption
$P1Integrity        = "SHA384"                 # Phase 1 integrity
$P1DHGroup          = "ECP256"                 # Phase 1 DH group (ECP256 = Group 19)
$P2Encryption       = "AES256"                 # Phase 2 encryption
$P2Integrity        = "SHA256128"              # Phase 2 integrity (SHA256128 = SHA256)
$P2PFSGroup         = "ECP256"                 # Phase 2 PFS group

$AppPorts           = @(443, 8080)             # Your application ports
#endregion

# ============================================================
# DO NOT EDIT BELOW THIS LINE
# ============================================================

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host ">>> $Text" -ForegroundColor Cyan
    Write-Host ("-" * 60) -ForegroundColor DarkGray
}

function Write-OK   { param([string]$T) Write-Host "    OK: $T" -ForegroundColor Green }
function Write-Warn { param([string]$T) Write-Host "  WARN: $T" -ForegroundColor Yellow }
function Write-Fail { param([string]$T) Write-Host "  FAIL: $T" -ForegroundColor Red }

# ============================================================
# STEP 0 — Validate prerequisites
# ============================================================
Write-Step "Validating prerequisites"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Fail "Must run as Administrator"
    exit 1
}
Write-OK "Running as Administrator"

$PSK = $env:VPN_PSK
if (-not $PSK) {
    Write-Fail "VPN_PSK environment variable not set. Run: `$env:VPN_PSK = 'your-psk'"
    exit 1
}
Write-OK "PSK loaded from environment variable ($($PSK.Length) characters)"

if ($LocalIP -eq "YOUR_SERVER_IP") {
    Write-Fail "Edit the CONFIGURATION section at the top of this script before running"
    exit 1
}
Write-OK "Configuration looks set"

# ============================================================
# STEP 1 — Remove any old native IPsec rules
# ============================================================
Write-Step "Removing old native IPsec rules"

Get-NetIPsecRule          | Remove-NetIPsecRule          -ErrorAction SilentlyContinue
Get-NetIPsecMainModeCryptoSet  | Remove-NetIPsecMainModeCryptoSet  -ErrorAction SilentlyContinue
Get-NetIPsecQuickModeCryptoSet | Remove-NetIPsecQuickModeCryptoSet -ErrorAction SilentlyContinue
Get-NetIPsecPhase1AuthSet | Remove-NetIPsecPhase1AuthSet -ErrorAction SilentlyContinue
Get-NetIPsecMainModeRule  | Remove-NetIPsecMainModeRule  -ErrorAction SilentlyContinue

Write-OK "Old native IPsec rules removed"
Write-Warn "WHY: Native IPsec tunnel mode ignores custom Phase 1 crypto and always uses DHGroup2/AES128/SHA1. It also sends IKEv1 which conflicts with RRAS IKEv2."

# ============================================================
# STEP 2 — Install RRAS if not already installed
# ============================================================
Write-Step "Installing RRAS"

$feature = Get-WindowsFeature -Name RemoteAccess
if (-not $feature.Installed) {
    Write-Host "    Installing RemoteAccess feature..." -ForegroundColor Yellow
    Install-WindowsFeature RemoteAccess, Routing, RSAT-RemoteAccess -IncludeManagementTools | Out-Null
    Write-OK "RemoteAccess installed"
} else {
    Write-OK "RemoteAccess already installed"
}

Set-Service RemoteAccess -StartupType Automatic
Start-Service RemoteAccess -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

$svc = Get-Service RemoteAccess
if ($svc.Status -ne "Running") {
    Write-Fail "RemoteAccess service not running. Open rrasmgmt.msc and configure as LAN router first."
    Write-Host "    Steps: Right click server > Configure and Enable > Custom > LAN Routing > Finish > Start Service" -ForegroundColor Yellow
    exit 1
}
Write-OK "RemoteAccess service running"

# ============================================================
# STEP 3 — Remove existing tunnel interfaces if they exist
# ============================================================
Write-Step "Cleaning up existing tunnel interfaces"

Remove-VpnS2SInterface -Name $PrimaryName -Force -ErrorAction SilentlyContinue
Remove-VpnS2SInterface -Name $BackupName  -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-OK "Existing interfaces cleared"

# ============================================================
# STEP 4 — Create primary tunnel
# ============================================================
Write-Step "Creating primary tunnel: $PrimaryName"

Add-VpnS2SInterface `
    -Name $PrimaryName `
    -Destination $PrimaryGateway `
    -Protocol Ikev2 `
    -AuthenticationMethod PSKOnly `
    -SharedSecret $PSK `
    -EncryptionType MaximumEncryption `
    -IPv4Subnet "$PrimarySubnet`:10" `
    -SALifeTime $PrimaryP2Life `
    -MMSALifeTime $PrimaryP1Life `
    -SourceIpAddress $LocalIP `
    -ResponderAuthenticationMethod PSKOnly

Set-VpnS2SInterface -Name $PrimaryName `
    -CustomPolicy `
    -EncryptionMethod $P1Encryption `
    -IntegrityCheckMethod $P1Integrity `
    -DHGroup $P1DHGroup `
    -CipherTransformConstants $P2Encryption `
    -AuthenticationTransformConstants $P2Integrity `
    -PfsGroup $P2PFSGroup

Write-OK "Primary tunnel created"
Write-OK "Phase 1: $P1Encryption / $P1Integrity / $P1DHGroup / $($PrimaryP1Life)s"
Write-OK "Phase 2: $P2Encryption / $P2Integrity / PFS $P2PFSGroup / $($PrimaryP2Life)s"

# ============================================================
# STEP 5 — Create backup tunnel
# ============================================================
Write-Step "Creating backup tunnel: $BackupName"

Add-VpnS2SInterface `
    -Name $BackupName `
    -Destination $BackupGateway `
    -Protocol Ikev2 `
    -AuthenticationMethod PSKOnly `
    -SharedSecret $PSK `
    -EncryptionType MaximumEncryption `
    -IPv4Subnet "$BackupSubnet`:10" `
    -SALifeTime $BackupP2Life `
    -MMSALifeTime $BackupP1Life `
    -SourceIpAddress $LocalIP `
    -ResponderAuthenticationMethod PSKOnly

Set-VpnS2SInterface -Name $BackupName `
    -CustomPolicy `
    -EncryptionMethod $P1Encryption `
    -IntegrityCheckMethod $P1Integrity `
    -DHGroup $P1DHGroup `
    -CipherTransformConstants $P2Encryption `
    -AuthenticationTransformConstants $P2Integrity `
    -PfsGroup $P2PFSGroup

Write-OK "Backup tunnel created"

# ============================================================
# STEP 6 — Set explicit traffic selectors
# ============================================================
Write-Step "Setting traffic selectors"
Write-Warn "WHY: RRAS uses wildcard 0.0.0.0/0 by default. Remote gateways with specific crypto maps (Cisco ASA etc.) will reject this with 'Crypto Map Policy not found'."

$ts_local_primary  = New-VpnTrafficSelector -TSPayloadId 0 -Type IPv4 -IPAddressRange $LocalIP,$LocalIP -PortRange 0,65535 -ProtocolId 0
$ts_remote_primary = New-VpnTrafficSelector -TSPayloadId 0 -Type IPv4 -IPAddressRange $PrimaryRemoteStart,$PrimaryRemoteEnd -PortRange 0,65535 -ProtocolId 0
Set-VpnS2SInterface -Name $PrimaryName -LocalVpnTrafficSelector $ts_local_primary -RemoteVpnTrafficSelector $ts_remote_primary
Write-OK "Primary TS: Local $LocalIP <-> Remote $PrimaryRemoteStart-$PrimaryRemoteEnd"

$ts_local_backup  = New-VpnTrafficSelector -TSPayloadId 0 -Type IPv4 -IPAddressRange $LocalIP,$LocalIP -PortRange 0,65535 -ProtocolId 0
$ts_remote_backup = New-VpnTrafficSelector -TSPayloadId 0 -Type IPv4 -IPAddressRange $BackupRemoteStart,$BackupRemoteEnd -PortRange 0,65535 -ProtocolId 0
Set-VpnS2SInterface -Name $BackupName -LocalVpnTrafficSelector $ts_local_backup -RemoteVpnTrafficSelector $ts_remote_backup
Write-OK "Backup  TS: Local $LocalIP <-> Remote $BackupRemoteStart-$BackupRemoteEnd"

# ============================================================
# STEP 7 — Open firewall ports
# ============================================================
Write-Step "Configuring firewall rules"

$existingRules = Get-NetFirewallRule -DisplayName "IKEv2-*" -ErrorAction SilentlyContinue
if ($existingRules) {
    $existingRules | Remove-NetFirewallRule
}

New-NetFirewallRule -DisplayName "IKEv2-UDP500-In"   -Direction Inbound  -Protocol UDP -LocalPort 500   -RemoteAddress $PrimaryGateway,$BackupGateway -Action Allow | Out-Null
New-NetFirewallRule -DisplayName "IKEv2-UDP500-Out"  -Direction Outbound -Protocol UDP -RemotePort 500  -RemoteAddress $PrimaryGateway,$BackupGateway -Action Allow | Out-Null
New-NetFirewallRule -DisplayName "IKEv2-UDP4500-In"  -Direction Inbound  -Protocol UDP -LocalPort 4500  -RemoteAddress $PrimaryGateway,$BackupGateway -Action Allow | Out-Null
New-NetFirewallRule -DisplayName "IKEv2-UDP4500-Out" -Direction Outbound -Protocol UDP -RemotePort 4500 -RemoteAddress $PrimaryGateway,$BackupGateway -Action Allow | Out-Null
Write-OK "IKEv2 firewall rules created (UDP 500 and 4500 restricted to gateway IPs)"

foreach ($port in $AppPorts) {
    New-NetFirewallRule -DisplayName "App-Out-$port" -Direction Outbound -Protocol TCP -RemotePort $port -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "App-In-$port"  -Direction Inbound  -Protocol TCP -LocalPort  $port -Action Allow -ErrorAction SilentlyContinue | Out-Null
}
Write-OK "Application port rules created: $($AppPorts -join ', ')"

# ============================================================
# STEP 8 — Restart RRAS and connect
# ============================================================
Write-Step "Restarting RRAS and connecting tunnels"

Restart-Service RemoteAccess -Force
Start-Sleep -Seconds 10
Write-OK "RRAS restarted"

Connect-VpnS2SInterface -Name $PrimaryName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 15
Connect-VpnS2SInterface -Name $BackupName  -ErrorAction SilentlyContinue
Start-Sleep -Seconds 10

# ============================================================
# STEP 9 — Final verification
# ============================================================
Write-Step "Final verification"

$p = Get-VpnS2SInterface -Name $PrimaryName
$b = Get-VpnS2SInterface -Name $BackupName

Write-Host ""
Write-Host "PRIMARY TUNNEL ($PrimaryName)" -ForegroundColor White
Write-Host "  Destination:  $($p.Destination[0])"
Write-Host "  Protocol:     $($p.Protocol)"
Write-Host "  Encryption:   $($p.EncryptionMethod)"
Write-Host "  Integrity:    $($p.IntegrityCheckMethod)"
Write-Host "  DH Group:     $($p.DHGroup)"
Write-Host "  PFS Group:    $($p.PfsGroup)"
Write-Host "  P1 Lifetime:  $($p.MMSALifeTime)s"
Write-Host "  P2 Lifetime:  $($p.SALifeTime)s"
Write-Host "  Local TS:     $($p.LocalVpnTrafficSelector.IPAddressRange)"
Write-Host "  Remote TS:    $($p.RemoteVpnTrafficSelector.IPAddressRange)"
$pColor = if ($p.ConnectionState -eq "Connected") { "Green" } else { "Red" }
Write-Host "  State:        $($p.ConnectionState)" -ForegroundColor $pColor
Write-Host "  LastError:    $($p.LastError)"

Write-Host ""
Write-Host "BACKUP TUNNEL ($BackupName)" -ForegroundColor White
Write-Host "  Destination:  $($b.Destination[0])"
Write-Host "  Protocol:     $($b.Protocol)"
Write-Host "  Encryption:   $($b.EncryptionMethod)"
Write-Host "  Integrity:    $($b.IntegrityCheckMethod)"
Write-Host "  DH Group:     $($b.DHGroup)"
Write-Host "  PFS Group:    $($b.PfsGroup)"
Write-Host "  P1 Lifetime:  $($b.MMSALifeTime)s"
Write-Host "  P2 Lifetime:  $($b.SALifeTime)s"
Write-Host "  Local TS:     $($b.LocalVpnTrafficSelector.IPAddressRange)"
Write-Host "  Remote TS:    $($b.RemoteVpnTrafficSelector.IPAddressRange)"
$bColor = if ($b.ConnectionState -eq "Connected") { "Green" } else { "Red" }
Write-Host "  State:        $($b.ConnectionState)" -ForegroundColor $bColor
Write-Host "  LastError:    $($b.LastError)"

Write-Host ""
if ($p.ConnectionState -eq "Connected" -and $b.ConnectionState -eq "Connected") {
    Write-Host "Both tunnels connected successfully." -ForegroundColor Green
} elseif ($p.ConnectionState -eq "Connected" -or $b.ConnectionState -eq "Connected") {
    Write-Host "One tunnel connected. Check the other one." -ForegroundColor Yellow
    Write-Host "Run: Get-VpnS2SInterface | Select-Object Name, ConnectionState, LastError" -ForegroundColor Yellow
} else {
    Write-Host "Tunnels not connected yet. Common causes:" -ForegroundColor Red
    Write-Host "  13816 = IKE Auth Failed  — check PSK and traffic selectors" -ForegroundColor Red
    Write-Host "  633   = Port in use       — configure RRAS as LAN router in rrasmgmt.msc" -ForegroundColor Red
    Write-Host "  789   = IPsec nego failed — check crypto parameters match remote side" -ForegroundColor Red
    Write-Host ""
    Write-Host "See docs/troubleshooting.md for detailed fixes." -ForegroundColor Yellow
}
