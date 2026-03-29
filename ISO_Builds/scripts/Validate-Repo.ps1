Write-Host "=== VALIDATING REPOSITORY INTEGRITY ===" -ForegroundColor Cyan

# $PSScriptRoot = repo/ISO_Builds/scripts
# $root = repo/ISO_Builds  ✅ correct root
$root = Split-Path $PSScriptRoot -Parent
$errors = @()

function Check-Path($Path, $Description) {
    if (!(Test-Path $Path)) {
        $script:errors += "[FAIL] Missing: $Description ($Path)"
    } else {
        Write-Host "[OK] $Description"
    }
}

Write-Host "`n[1] Required directory structure"
Check-Path "$root"                         "Root ISO_Builds folder"
Check-Path "$root\iso"                     "ISO folder"
Check-Path "$root\updates\2022"            "Updates 2022 folder"
Check-Path "$root\updates\2025"            "Updates 2025 folder"
Check-Path "$root\gpo"                     "GPO folder"
Check-Path "$root\scripts"                 "Scripts folder"

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
    Check-Path "$root\scripts\$file" $file
}

Write-Host "`n[3] GPO Baseline Files"
Check-Path "$root\gpo\Security.csv" "Security.csv baseline"
Check-Path "$root\gpo\Audit.ini"    "Audit.ini baseline"

Write-Host "`n[4] Check ADK (oscdimg.exe) — skipping fatal check until ADK is installed"

$Oscd = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

if (Test-Path $Oscd) {
    Write-Host "[OK] ADK Deployment Tools found"
} else {
    Write-Host "[WARNING] ADK not installed yet — skipping check"
}

Write-Host "`n[5] Check DISM"
dism /? | Out-Null
if ($LASTEXITCODE -ne 0) {
    $errors += "[FAIL] DISM not functional"
} else {
    Write-Host "[OK] DISM OK"
}

Write-Host "`n[6] Validate config.json"
try {
    $config = Get-Content "$root\scripts\config.json" | ConvertFrom-Json
    Write-Host "[OK] config.json parsed successfully"
} catch {
    $errors += "[FAIL] config.json is not valid JSON"
}

Write-Host "`n=== RESULTS ==="
if ($errors.Count -eq 0) {
    Write-Host "[OK] ALL CHECKS PASSED - repository structure is valid." -ForegroundColor Green
} else {
    Write-Host "[WARNING] Issues found:" -ForegroundColor Yellow
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}