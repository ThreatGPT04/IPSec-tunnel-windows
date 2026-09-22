# ============================================================
# 02-create-tunnel.ps1 — Create primary and backup tunnels
# ============================================================

. "$PSScriptRoot\..\config\tunnel-params.ps1"

function New-IKEv2Tunnel {
    param(
        [string]$Name,
        [string]$Gateway,
        [string]$Subnet,
        [string]$LocalIP,
        [string]$PSK,
        [int]$P1Life,
        [int]$P2Life,
        [string]$P1Encryption,
        [string]$P1Integrity,
        [string]$P1DH,
        [string]$P2Encryption,
        [string]$P2Integrity,
        [string]$P2PFS
    )

    Write-Host "Creating $Name..." -ForegroundColor Cyan

    Remove-VpnS2SInterface -Name $Name -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Add-VpnS2SInterface `
        -Name $Name `
        -Destination $Gateway `
        -Protocol Ikev2 `
        -AuthenticationMethod PSKOnly `
        -SharedSecret $PSK `
        -EncryptionType MaximumEncryption `
        -IPv4Subnet "$Subnet`:10" `
        -SALifeTime $P2Life `
        -MMSALifeTime $P1Life `
        -SourceIpAddress $LocalIP `
        -ResponderAuthenticationMethod PSKOnly

    Set-VpnS2SInterface -Name $Name `
        -CustomPolicy `
        -EncryptionMethod $P1Encryption `
        -IntegrityCheckMethod $P1Integrity `
        -DHGroup $P1DH `
        -CipherTransformConstants $P2Encryption `
        -AuthenticationTransformConstants $P2Integrity `
        -PfsGroup $P2PFS

    Write-Host "$Name created" -ForegroundColor Green
}

New-IKEv2Tunnel -Name $PrimaryName -Gateway $PrimaryGateway -Subnet $PrimarySubnet `
    -LocalIP $LocalIP -PSK $PSK -P1Life $PrimaryP1Life -P2Life $PrimaryP2Life `
    -P1Encryption $P1Encryption -P1Integrity $P1Integrity -P1DH $P1DHGroup `
    -P2Encryption $P2Encryption -P2Integrity $P2Integrity -P2PFS $P2PFSGroup

New-IKEv2Tunnel -Name $BackupName -Gateway $BackupGateway -Subnet $BackupSubnet `
    -LocalIP $LocalIP -PSK $PSK -P1Life $BackupP1Life -P2Life $BackupP2Life `
    -P1Encryption $P1Encryption -P1Integrity $P1Integrity -P1DH $P1DHGroup `
    -P2Encryption $P2Encryption -P2Integrity $P2Integrity -P2PFS $P2PFSGroup

Write-Host ""
Write-Host "Tunnels created. Run 03-set-traffic-selectors.ps1 next." -ForegroundColor Yellow
Write-Host "Do not connect yet — traffic selectors must be set first." -ForegroundColor Red
