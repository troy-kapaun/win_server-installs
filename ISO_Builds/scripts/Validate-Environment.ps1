Write-Host "=== VALIDATING ENVIRONMENT ==="

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrator")) {
    Write-Host "❌ Run as Administrator"; exit 1
}

$Oscd = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
if (!(Test-Path $Oscd)) { Write-Host "❌ Windows ADK not installed"; exit 1 }
Write-Host "✅ ADK OK"

dism /? | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "❌ DISM not working"; exit 1 }
Write-Host "✅ DISM OK"

Write-Host "✅ Validation passed"