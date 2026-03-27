Write-Host "=== VALIDATING REPOSITORY INTEGRITY ===" -ForegroundColor Cyan

$root = Split-Path $PSScriptRoot -Parent
$errors = @()

function Check-Path($Path, $Description) {
    if (!(Test-Path $Path)) {
        $errors += "❌ Missing: $Description ($Path)"
    } else {
        Write-Host "✅ $Description"
    }
}

Write-Host "`n[1] Required directory structure"
Check-Path "$root\ISO_Builds"                        "Root ISO_Builds folder"
Check-Path "$root\ISO_Builds\iso"                    "ISO folder"
Check-Path "$root\ISO_Builds\updates\2022"           "Updates 2022 folder"
Check-Path "$root\ISO_Builds\updates\2025"           "Updates 2025 folder"
Check-Path "$root\ISO_Builds\gpo"                    "GPO folder"
Check-Path "$root\ISO_Builds\scripts"                "Scripts folder"

Write-Host "`n[2] Required script files"
$requiredScripts = @(
    "Harden-WIM.ps1",
    "Harden-WIM-MultiIndex.ps1",
    "Build-All.ps1",
    "Cleanup-WIM.ps1",
    "Validate-Environment.ps1",
    "Preflight-Host.ps1",
    "Auto-Update-MSUs.ps1",
    "config.json"
)

foreach ($file in $requiredScripts) {
    Check-Path "$root\ISO_Builds\scripts\$file" $file
}

Write-Host "`n[3] GPO Baseline Files"
Check-Path "$root\ISO_Builds\gpo\Security.csv" "Security.csv baseline"
Check-Path "$root\ISO_Builds\gpo\Audit.ini"    "Audit.ini baseline"

Write-Host "`n[4] Check ADK (oscdimg.exe)"
$Oscd = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
Check-Path $Oscd "Windows ADK Deployment Tools (oscdimg.exe)"

Write-Host "`n[5] Check DISM"
dism /? | Out-Null
if ($LASTEXITCODE -ne 0) {
    $errors += "❌ DISM not functional"
} else {
    Write-Host "✅ DISM OK"
}

Write-Host "`n[6] Validate config.json"
try {
    $config = Get-Content "$root\ISO_Builds\scripts\config.json" | ConvertFrom-Json
    Write-Host "✅ config.json parsed successfully"
} catch {
    $errors += "❌ config.json is not valid JSON"
}

Write-Host "`n=== RESULTS ==="
if ($errors.Count -eq 0) {
    Write-Host "✅ ALL CHECKS PASSED — repository structure is valid." -ForegroundColor Green
} else {
    Write-Host "⚠️ Issues found:" -ForegroundColor Yellow
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}