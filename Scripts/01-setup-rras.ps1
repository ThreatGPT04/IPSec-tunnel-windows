# ============================================================
# 01-setup-rras.ps1 — Install and start RRAS
# Run once before creating tunnels
# ============================================================

$feature = Get-WindowsFeature -Name RemoteAccess
if ($feature.Installed) {
    Write-Host "RemoteAccess already installed" -ForegroundColor Green
} else {
    Write-Host "Installing RemoteAccess..." -ForegroundColor Yellow
    Install-WindowsFeature RemoteAccess, Routing, RSAT-RemoteAccess -IncludeManagementTools
    Write-Host "Installed" -ForegroundColor Green
}

Set-Service RemoteAccess -StartupType Automatic
Start-Service RemoteAccess -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

$svc = Get-Service RemoteAccess
Write-Host "RemoteAccess: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' })

Write-Host ""
Write-Host "Next step: Open rrasmgmt.msc" -ForegroundColor Yellow
Write-Host "Right click server > Configure and Enable > Custom Configuration > LAN Routing > Finish > Start Service" -ForegroundColor Yellow
