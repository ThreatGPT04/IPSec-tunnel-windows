# ============================================================
# 06-cleanup.ps1 — Remove all tunnels and native IPsec rules
# ============================================================

. "$PSScriptRoot\..\config\tunnel-params.ps1"

Remove-VpnS2SInterface -Name $PrimaryName -Force -ErrorAction SilentlyContinue
Remove-VpnS2SInterface -Name $BackupName  -Force -ErrorAction SilentlyContinue
Write-Host "Tunnels removed" -ForegroundColor Green

Get-NetIPsecRule          | Remove-NetIPsecRule          -ErrorAction SilentlyContinue
Get-NetIPsecMainModeCryptoSet  | Remove-NetIPsecMainModeCryptoSet  -ErrorAction SilentlyContinue
Get-NetIPsecQuickModeCryptoSet | Remove-NetIPsecQuickModeCryptoSet -ErrorAction SilentlyContinue
Get-NetIPsecPhase1AuthSet | Remove-NetIPsecPhase1AuthSet -ErrorAction SilentlyContinue
Get-NetIPsecMainModeRule  | Remove-NetIPsecMainModeRule  -ErrorAction SilentlyContinue
Write-Host "Native IPsec rules removed" -ForegroundColor Green

Restart-Service RemoteAccess -Force
Write-Host "Done" -ForegroundColor Green
