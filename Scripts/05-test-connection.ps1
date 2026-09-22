# ============================================================
# 05-test-connection.ps1 — Connect tunnels and test ports
# ============================================================

. "$PSScriptRoot\..\config\tunnel-params.ps1"

# Set your test hosts and ports
$PrimaryTestHost = $PrimaryRemoteStart
$PrimaryTestPort = 443                   # change to your application port

$BackupTestHost  = $BackupRemoteStart
$BackupTestPort  = 443                   # change to your application port

function Test-Tunnel {
    param(
        [string]$Name,
        [string]$Host,
        [int]$Port
    )

    Write-Host "--- $Name ---" -ForegroundColor Cyan

    Connect-VpnS2SInterface -Name $Name -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 15

    $t = Get-VpnS2SInterface -Name $Name
    $color = if ($t.ConnectionState -eq "Connected") { "Green" } else { "Red" }
    Write-Host "State:     $($t.ConnectionState)" -ForegroundColor $color
    Write-Host "LastError: $($t.LastError)"

    switch ($t.LastError) {
        13816 { Write-Host "IKE Auth Failed — check PSK and traffic selectors" -ForegroundColor Red }
        633   { Write-Host "Port in use — RRAS not configured as LAN router" -ForegroundColor Red }
        789   { Write-Host "IPsec negotiation failed" -ForegroundColor Red }
        0     { Write-Host "No error" -ForegroundColor Green }
    }

    Write-Host ""
    Write-Host "Testing $Host`:$Port..." -ForegroundColor Yellow
    $r = Test-NetConnection -ComputerName $Host -Port $Port -WarningAction SilentlyContinue
    Write-Host "Ping: $($r.PingSucceeded)   TCP: $($r.TcpTestSucceeded)   Via: $($r.InterfaceAlias)" -ForegroundColor $(if ($r.TcpTestSucceeded) { 'Green' } else { 'Red' })
    Write-Host ""
}

Write-Host "Time: $(Get-Date)"
Write-Host ""
Test-Tunnel -Name $PrimaryName -Host $PrimaryTestHost -Port $PrimaryTestPort
Test-Tunnel -Name $BackupName  -Host $BackupTestHost  -Port $BackupTestPort
