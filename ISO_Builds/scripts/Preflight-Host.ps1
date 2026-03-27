Write-Host "=== PREFLIGHT HOST CHECK ==="

$build = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
Write-Host "Host build: $build"

$vbs = Get-CimInstance -ClassName Win32_DeviceGuard | Select-Object -ExpandProperty SecurityServicesRunning
if ($vbs -contains 1) { Write-Host "⚠️ VBS enabled" } else { Write-Host "✅ VBS disabled" }

if (!(Test-Path "C:\Windows\System32\wimmount.sys")) { Write-Host "❌ wimmount.sys missing"; exit 1 }
Write-Host "✅ wimmount.sys OK"

$mounts = dism /Get-MountStatus | Select-String "Mounted"
if ($mounts) { Write-Host "⚠️ Stale WIM mounts present" } else { Write-Host "✅ No stale mounts" }