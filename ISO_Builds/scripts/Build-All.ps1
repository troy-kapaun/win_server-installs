param(
    [Parameter(Mandatory=$true)]
    [string]$Iso2022,

    [Parameter(Mandatory=$true)]
    [string]$Iso2025
)

$Root = Split-Path $PSScriptRoot -Parent

$Updates2022 = "$Root\updates\2022"
$Updates2025 = "$Root\updates\2025"
$GPO         = "$Root\gpo"

$Out2022 = "C:\WIMBUILD\Hardened2022.iso"
$Out2025 = "C:\WIMBUILD\Hardened2025.iso"

# Hardening 2022
& "$PSScriptRoot\Harden-WIM.ps1" `
    -IsoPath $Iso2022 `
    -UpdatesPath $Updates2022 `
    -GpoPath $GPO `
    -OutputIso $Out2022

# Hardening 2025
& "$PSScriptRoot\Harden-WIM.ps1" `
    -IsoPath $Iso2025 `
    -UpdatesPath $Updates2025 `
    -GpoPath $GPO `
    -OutputIso $Out2025

Write-Host "✅ Hardened Server 2022 ISO: $Out2022"
Write-Host "✅ Hardened Server 2025 ISO: $Out2025"