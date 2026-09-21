# ============================================================
# tunnel-params.ps1 — Edit this file before running any scripts
# ============================================================

# Your server IP
$LocalIP = "YOUR_SERVER_IP"                    # e.g. 10.0.0.100

# PSK — never hardcode here, load from environment variable
$PSK = $env:VPN_PSK
if (-not $PSK) {
    Write-Host "ERROR: Set your PSK first: `$env:VPN_PSK = 'your-psk'" -ForegroundColor Red
    exit 1
}

# ---- Primary Tunnel ----
$PrimaryName        = "VPN-Primary"
$PrimaryGateway     = "REMOTE_GATEWAY_IP"      # e.g. 203.0.113.1
$PrimarySubnet      = "REMOTE_SUBNET/MASK"     # e.g. 10.1.0.0/24
$PrimaryRemoteStart = "REMOTE_SUBNET_START"    # e.g. 10.1.0.0
$PrimaryRemoteEnd   = "REMOTE_SUBNET_END"      # e.g. 10.1.0.255
$PrimaryP1Life      = 86400                    # Phase 1 lifetime in seconds
$PrimaryP2Life      = 28800                    # Phase 2 lifetime in seconds

# ---- Backup Tunnel ----
$BackupName        = "VPN-Backup"
$BackupGateway     = "BACKUP_GATEWAY_IP"       # e.g. 203.0.113.2
$BackupSubnet      = "BACKUP_REMOTE_SUBNET"    # e.g. 10.2.0.1/32
$BackupRemoteStart = "BACKUP_REMOTE_START"     # e.g. 10.2.0.1
$BackupRemoteEnd   = "BACKUP_REMOTE_END"       # e.g. 10.2.0.1
$BackupP1Life      = 28800
$BackupP2Life      = 28800

# ---- Phase 1 Crypto ----
$P1Encryption = "AES256"     # AES128 | AES192 | AES256
$P1Integrity  = "SHA384"     # SHA256 | SHA384 | SHA512
$P1DHGroup    = "ECP256"     # DH14 | ECP256 (Group19) | ECP384 (Group20)

# ---- Phase 2 Crypto ----
$P2Encryption = "AES256"     # AES128 | AES192 | AES256
$P2Integrity  = "SHA256128"  # SHA256128 (=SHA256) | SHA384 | SHA512
$P2PFSGroup   = "ECP256"     # DH14 | ECP256 | ECP384

# ---- Application Ports ----
$AppPorts = @(443, 8080)     # Add your application ports here
