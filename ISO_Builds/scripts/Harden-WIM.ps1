param(
    [Parameter(Mandatory=$true)]
    [string]$IsoPath,

    [Parameter(Mandatory=$true)]
    [string]$UpdatesPath,

    [Parameter(Mandatory=$true)]
    [string]$GpoPath,

    [Parameter(Mandatory=$true)]
    [string]$OutputIso,

    [switch]$DryRun
)

Write-Host "==============================================="
Write-Host " HARDENING IMAGE: $IsoPath"
Write-Host " Output ISO     : $OutputIso"
Write-Host "===============================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "`n*** DRY RUN — NO CHANGES WILL BE MADE ***`n" -ForegroundColor Yellow
    Write-Host "ISO Path:      $IsoPath"
    Write-Host "Updates Path:  $UpdatesPath"
    Write-Host "GPO Path:      $GpoPath"
    Write-Host "Output ISO:    $OutputIso"
    Write-Host ""

    Write-Host "Validating paths..."

    foreach ($p in @($IsoPath,$UpdatesPath,$GpoPath)) {
        if (!(Test-Path $p)) { Write-Host "❌ Missing: $p" } else { Write-Host "✅ Found: $p" }
    }

    # Validate output directory
    $OutDir = Split-Path $OutputIso -Parent
    if (!(Test-Path $OutDir)) {
        Write-Host "❌ Output directory does not exist: $OutDir"
    } else {
        Write-Host "✅ Output directory exists: $OutDir"
    }

    Write-Host "`nSimulated next steps:"
    Write-Host "- Would mount ISO"
    Write-Host "- Would extract ISO"
    Write-Host "- Would convert ESD → WIM (if necessary)"
    Write-Host "- Would mount WIM Index 2"
    Write-Host "- Would inject MSU updates"
    Write-Host "- Would apply Security.csv baseline"
    Write-Host "- Would apply GPO (GroupPolicy + ADMX)"
    Write-Host "- Would set up SetupComplete.cmd audit restore"
    Write-Host "- Would commit WIM and build final ISO"
    Write-Host "`nDry‑run completed — exiting before image operations."
    exit 0
}

# (Full script continues unchanged…)

# ===============================
# 0. Prepare Working Directories
# ===============================
$Base = "C:\WIMBUILD\Work"
if (Test-Path $Base) { Remove-Item $Base -Recurse -Force }
New-Item $Base -ItemType Directory | Out-Null

$MountISO = "$Base\ISO_MOUNT"
$Extract  = "$Base\ISO_EXTRACT"
$MountWIM = "$Base\WIM_MOUNT"

New-Item $MountISO, $Extract, $MountWIM -ItemType Directory -Force | Out-Null


# ===============================
# 1. Copy ISO Local & Mount
# ===============================
Write-Host "[1] Mounting ISO..."

$LocalISO = "C:\WIMBUILD\input.iso"
Copy-Item $IsoPath $LocalISO -Force

$IsoObj = Mount-DiskImage -ImagePath $LocalISO -PassThru
$Drive  = ($IsoObj | Get-Volume).DriveLetter + ":"

Write-Host "Mounted ISO at $Drive"


# ===============================
# 2. Extract ISO Contents
# ===============================
Write-Host "[2] Extracting ISO..."
robocopy "$Drive\" $Extract /MIR | Out-Null


# ===============================
# 3. Convert ESD → WIM if needed
# ===============================
Write-Host "[3] Checking WIM/ESD..."

$WIM = "$Extract\sources\install.wim"
$ESD = "$Extract\sources\install.esd"

if (Test-Path $ESD) {
    Write-Host "Converting install.esd → install.wim ..."
    dism /Export-Image /SourceImageFile:$ESD /DestinationImageFile:$WIM /Compress:max /SourceIndex:1
    Remove-Item $ESD -Force
}

if (!(Test-Path $WIM)) {
    Write-Host "❌ install.wim NOT FOUND!"
    exit 1
}


# ===============================
# 4. Mount WIM
# ===============================
Write-Host "[4] Mounting WIM..."

# always harden Standard Edition with Desktop Experience = Index 2
$Index = 2  

dism /Mount-WIM /WimFile:$WIM /Index:$Index /MountDir:$MountWIM

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to mount WIM"
    exit 1
}


# ===============================
# 5. Add MSU Updates
# ===============================
Write-Host "[5] Integrating updates..."

if (Test-Path $UpdatesPath) {
    foreach ($u in Get-ChildItem $UpdatesPath -Filter *.msu) {
        Write-Host "Adding update: $($u.Name)"
        dism /Image:$MountWIM /Add-Package /PackagePath:$u.FullName
    }
}
else {
    Write-Host "No updates found."
}


# ===============================
# 6. Load Offline Registry
# ===============================
Write-Host "[6] Loading offline registry..."

reg load HKLM\OFFSOFT "$MountWIM\Windows\System32\Config\SOFTWARE" | Out-Null
reg load HKLM\OFFSYS  "$MountWIM\Windows\System32\Config\SYSTEM"   | Out-Null
reg load HKLM\OFFSEC  "$MountWIM\Windows\System32\Config\SECURITY" | Out-Null
reg load HKLM\OFFSAM  "$MountWIM\Windows\System32\Config\SAM"      | Out-Null


# ===============================
# 7. Apply CIS / Security.csv
# ===============================
Write-Host "[7] Applying Security Baseline (Security.csv)..."

$CSV = Join-Path $GpoPath "Security.csv"
$DB  = "$MountWIM\Windows\Security\Database\defltbase.sdb"

secedit /configure /db $DB /cfg $CSV /areas SECURITYPOLICY USER_RIGHTS /quiet


# ===============================
# 8. Apply GPO: GroupPolicy + ADMX
# ===============================
Write-Host "[8] Injecting GPO baseline..."

Copy-Item "$GpoPath\GroupPolicy"        "$MountWIM\Windows\System32\" -Recurse -Force
Copy-Item "$GpoPath\PolicyDefinitions" "$MountWIM\Windows\"           -Recurse -Force


# ===============================
# 9. First Boot Auditpol Restore
# ===============================
Write-Host "[9] Adding SetupComplete.cmd..."

$Scripts = "$MountWIM\Windows\Setup\Scripts"
New-Item $Scripts -ItemType Directory -Force | Out-Null

Set-Content "$Scripts\SetupComplete.cmd" @"
@echo off
auditpol /restore /file:"C:\Windows\Setup\Scripts\Audit.ini"
del C:\Windows\Setup\Scripts\SetupComplete.cmd
"@

Copy-Item "$GpoPath\Audit.ini" "$Scripts\Audit.ini" -Force


# ===============================
# 10. Cleanup Offline Registry
# ===============================
Write-Host "[10] Unloading registry hives..."

reg unload HKLM\OFFSOFT | Out-Null
reg unload HKLM\OFFSYS  | Out-Null
reg unload HKLM\OFFSEC  | Out-Null
reg unload HKLM\OFFSAM  | Out-Null


# ===============================
# 11. Commit WIM
# ===============================
Write-Host "[11] Committing WIM..."
dism /Unmount-WIM /MountDir:$MountWIM /Commit


# ===============================
# 12. Build Hardened ISO
# ===============================
Write-Host "[12] Building final ISO..."

$Oscd = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

& $Oscd -m -o -u2 -udfver102 $Extract $OutputIso


Write-Host "==============================================="
Write-Host " ✅ Hardened image built:"
Write-Host "     $OutputIso"
Write-Host "==============================================="