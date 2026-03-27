Write-Host "=== TEST PIPELINE SIMULATION ===" -ForegroundColor Cyan

$root = Split-Path $PSScriptRoot -Parent

$iso2022 = Get-ChildItem "$root\ISO_Builds\iso" | Where-Object { $_.Name -match "2022" } | Select-Object -Expand FullName -ErrorAction Ignore
$iso2025 = Get-ChildItem "$root\ISO_Builds\iso" | Where-Object { $_.Name -match "2025" } | Select-Object -Expand FullName -ErrorAction Ignore

Write-Host "`n[1] ISO discovery..."
if (!$iso2022) { Write-Host "❌ No 2022 ISO found"; } else { Write-Host "✅ Found 2022 ISO: $iso2022" }
if (!$iso2025) { Write-Host "❌ No 2025 ISO found"; } else { Write-Host "✅ Found 2025 ISO: $iso2025" }

Write-Host "`n[2] Simulating Build-All.ps1 execution..."
Write-Host "→ Would run: Build-All.ps1 -Iso2022 `"$iso2022`" -Iso2025 `"$iso2025`""
Write-Host "✅ Script call simulated"

Write-Host "`n[3] Simulating output artifact generation..."
Write-Host "→ Would generate Hardened2022.iso"
Write-Host "→ Would generate Hardened2025.iso"

Write-Host "`n✅ Pipeline simulation complete (no WIM operations performed)."