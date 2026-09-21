# ============================================================
# 04-verify-tunnel.ps1 — Verify full tunnel configuration
# ============================================================

. "$PSScriptRoot\..\config\tunnel-params.ps1"

function Show-Tunnel {
    param([string]$Name)

    Write-Host "--- $Name ---" -ForegroundColor Cyan
    $t = Get-VpnS2SInterface -Name $Name -ErrorAction SilentlyContinue

    if (-not $t) {
        Write-Host "Not found" -ForegroundColor Red
        return
    }

    Write-Host "Destination:      $($t.Destination[0])"
    Write-Host "Source:           $($t.SourceIpAddress)"
    Write-Host "Protocol:         $($t.Protocol)"
    Write-Host "DH Group:         $($t.DHGroup)"
    Write-Host "Encryption:       $($t.EncryptionMethod)"
    Write-Host "Integrity:        $($t.IntegrityCheckMethod)"
    Write-Host "PFS Group:        $($t.PfsGroup)"
    Write-Host "Phase2 Cipher:    $($t.CipherTransformConstants)"
    Write-Host "Phase2 Auth:      $($t.AuthenticationTransformConstants)"
    Write-Host "Phase1 Lifetime:  $($t.MMSALifeTime) seconds"
    Write-Host "Phase2 Lifetime:  $($t.SALifeTime) seconds"
    Write-Host "Auth Method:      $($t.AuthenticationMethod)"
    Write-Host "Subnet:           $($t.IPv4Subnet)"
    Write-Host "Local TS:         $($t.LocalVpnTrafficSelector.IPAddressRange)"
    Write-Host "Remote TS:        $($t.RemoteVpnTrafficSelector.IPAddressRange)"

    $color = switch ($t.ConnectionState) {
        "Connected"    { "Green" }
        "Disconnected" { "Yellow" }
        default        { "Red" }
    }
    Write-Host "State:            $($t.ConnectionState)" -ForegroundColor $color
    Write-Host "LastError:        $($t.LastError)"
    Write-Host ""
}

Write-Host "=== RRAS SERVICE ===" -ForegroundColor White
$svc = Get-Service RemoteAccess
Write-Host "Status: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' })
Write-Host ""

Write-Host "=== TUNNEL CONFIGURATION ===" -ForegroundColor White
Show-Tunnel -Name $PrimaryName
Show-Tunnel -Name $BackupName

Write-Host "=== NATIVE IPSEC RULES (should be empty) ===" -ForegroundColor White
$rules = Get-NetIPsecRule -ErrorAction SilentlyContinue
if ($rules) {
    Write-Host "WARNING: Native IPsec rules still active. These send IKEv1 traffic." -ForegroundColor Red
    $rules | Select-Object DisplayName, Enabled | Format-Table -AutoSize
} else {
    Write-Host "Clean — no native IPsec rules active" -ForegroundColor Green
}
