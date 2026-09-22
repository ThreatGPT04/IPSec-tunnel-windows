# ============================================================
# 03-set-traffic-selectors.ps1 — Set explicit traffic selectors
#
# WHY THIS MATTERS:
# RRAS uses wildcard traffic selectors 0.0.0.0/0 by default.
# Remote gateways with specific crypto maps (Cisco ASA, Palo Alto etc.)
# will reject the tunnel with "Crypto Map Policy not found".
# Always run this after creating tunnels.
# ============================================================

. "$PSScriptRoot\..\config\tunnel-params.ps1"

function Set-TrafficSelectors {
    param(
        [string]$TunnelName,
        [string]$LocalIP,
        [string]$RemoteStart,
        [string]$RemoteEnd
    )

    Write-Host "Setting traffic selectors for $TunnelName" -ForegroundColor Cyan

    $ts_local = New-VpnTrafficSelector `
        -TSPayloadId 0 `
        -Type IPv4 `
        -IPAddressRange $LocalIP, $LocalIP `
        -PortRange 0, 65535 `
        -ProtocolId 0

    $ts_remote = New-VpnTrafficSelector `
        -TSPayloadId 0 `
        -Type IPv4 `
        -IPAddressRange $RemoteStart, $RemoteEnd `
        -PortRange 0, 65535 `
        -ProtocolId 0

    Set-VpnS2SInterface -Name $TunnelName `
        -LocalVpnTrafficSelector $ts_local `
        -RemoteVpnTrafficSelector $ts_remote

    $t = Get-VpnS2SInterface -Name $TunnelName
    Write-Host "  Local TS:  $($t.LocalVpnTrafficSelector.IPAddressRange)" -ForegroundColor Gray
    Write-Host "  Remote TS: $($t.RemoteVpnTrafficSelector.IPAddressRange)" -ForegroundColor Gray
    Write-Host "$TunnelName traffic selectors set" -ForegroundColor Green
}

Set-TrafficSelectors -TunnelName $PrimaryName -LocalIP $LocalIP `
    -RemoteStart $PrimaryRemoteStart -RemoteEnd $PrimaryRemoteEnd

Set-TrafficSelectors -TunnelName $BackupName -LocalIP $LocalIP `
    -RemoteStart $BackupRemoteStart -RemoteEnd $BackupRemoteEnd

Write-Host ""
Write-Host "Restarting RRAS..." -ForegroundColor Yellow
Restart-Service RemoteAccess -Force
Start-Sleep -Seconds 10
Write-Host "Done. Run 04-verify-tunnel.ps1 to confirm configuration." -ForegroundColor Green
