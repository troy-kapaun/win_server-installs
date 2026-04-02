param(
    [Parameter(Mandatory=$true)]
    [string]$IsoPath,

    [Parameter(Mandatory=$true)]
    [string]$UpdatesPath,

    [Parameter(Mandatory=$true)]
    [string]$GpoPath,

    [Parameter(Mandatory=$true)]
    [string]$OutputIso,

    [ValidateSet('CST','EST','MST','PST')]
    [string]$Timezone,

    [string]$UnattendPath,

    [switch]$DryRun
)

Write-Host "==============================================="
Write-Host " HARDENING IMAGE: $IsoPath"
Write-Host " Output ISO     : $OutputIso"
Write-Host "===============================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "`n*** DRY RUN - NO CHANGES WILL BE MADE ***`n" -ForegroundColor Yellow
    Write-Host "ISO Path:      $IsoPath"
    Write-Host "Updates Path:  $UpdatesPath"
    Write-Host "GPO Path:      $GpoPath"
    Write-Host "Output ISO:    $OutputIso"
    Write-Host ""

    Write-Host "Validating paths..."

    foreach ($p in @($IsoPath,$UpdatesPath,$GpoPath)) {
        if (!(Test-Path $p)) { Write-Host "[FAIL] Missing: $p" } else { Write-Host "[OK] Found: $p" }
    }

    # Validate output directory
    $OutDir = Split-Path $OutputIso -Parent
    if (!(Test-Path $OutDir)) {
        Write-Host "[FAIL] Output directory does not exist: $OutDir"
    } else {
        Write-Host "[OK] Output directory exists: $OutDir"
    }

    Write-Host "`nSimulated next steps:"
    Write-Host "- Prepare Working Directories"
    Write-Host "- Would mount ISO"
    Write-Host "- Would extract ISO"
    Write-Host "- Would convert ESD -> WIM (if necessary)"
    Write-Host "- Would mount WIM Index 2"
    Write-Host "- Would inject MSU updates"
    Write-Host "- Load Offline Registry"
    Write-Host "- Would apply Apply CIS GPO: GroupPolicy + ADMX"
    Write-Host "- Would set up SetupComplete.cmd audit restore & apply security baseline"
    if ($Timezone) {
        Write-Host "- Would inject unattend_$Timezone.xml into Sysprep + Panther"
    }
    Write-Host "- Would commit WIM and build final ISO"
    Write-Host "`nDry-run completed - exiting before image operations."
    exit 0
}

# (Full script continues below)

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
robocopy "$Drive\" $Extract /E /COPY:DT /R:3 /W:1
$rcExit = $LASTEXITCODE
Write-Host "Robocopy exit code: $rcExit"
if ($rcExit -ge 8) {
    Write-Host "[FAIL] robocopy failed with exit code $rcExit"
    exit 1
}

# Only remove read-only from install.wim which DISM needs to modify.
# Leave boot files (BCD, efisys_noprompt.bin, etfsboot.com) untouched
# to preserve their original ISO attributes.
Write-Host "Clearing read-only on install.wim..."
attrib -R "$Extract\sources\install.wim"

# Verify critical boot files were extracted intact
Write-Host "Verifying boot files..."
$bootFileHashes = @{}
foreach ($bf in @(
    "$Extract\boot\etfsboot.com",
    "$Extract\efi\microsoft\boot\efisys_noprompt.bin",
    "$Extract\efi\microsoft\boot\BCD"
)) {
    if (Test-Path $bf) {
        $fi = Get-Item $bf
        $hash = (Get-FileHash $bf -Algorithm SHA256).Hash
        $bootFileHashes[$bf] = $hash
        Write-Host "  [OK] $bf ($($fi.Length) bytes) SHA256=$hash"
    } else {
        Write-Host "  [FAIL] Missing boot file: $bf"
        exit 1
    }
}

# Free disk space: dismount and delete the ISO copy now that extraction is complete
Write-Host "Dismounting ISO and cleaning up to free disk space..."
Dismount-DiskImage -ImagePath $LocalISO | Out-Null
Remove-Item $LocalISO -Force

# ===============================
# 3. Convert ESD -> WIM if needed
# ===============================
Write-Host "[3] Checking WIM/ESD..."

$WIM = "$Extract\sources\install.wim"
$ESD = "$Extract\sources\install.esd"

if (Test-Path $ESD) {
    Write-Host "Converting install.esd -> install.wim ..."
    dism /Export-Image /SourceImageFile:$ESD /DestinationImageFile:$WIM /Compress:max /SourceIndex:1
    Remove-Item $ESD -Force
}

if (!(Test-Path $WIM)) {
    Write-Host "[FAIL] install.wim NOT FOUND!"
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
    Write-Host "[FAIL] Failed to mount WIM"
    exit 1
}

# ===============================
# 5. Add MSU Updates
# ===============================
Write-Host "[5] Integrating updates..."

if (Test-Path $UpdatesPath) {
    Write-Host "Updates directory: $UpdatesPath"
    Write-Host "Directory contents:"
    Get-ChildItem $UpdatesPath -Recurse | ForEach-Object {
        Write-Host "  $($_.FullName) ($([math]::Round($_.Length/1MB,1)) MB)"
    }

    $pkgs = Get-ChildItem $UpdatesPath -Include '*.msu','*.cab' -Recurse
    Write-Host "Found $(@($pkgs).Count) update package(s) to inject"

    if ($pkgs) {
        foreach ($u in $pkgs) {
            $pkgPath = $u.FullName
            Write-Host "Adding update: $($u.Name) ($([math]::Round($u.Length/1MB,1)) MB)"

            if ($u.Extension -eq '.msu') {
                # Peek inside the MSU to detect its packaging format.
                # Server 2025 / Win11 24H2 uses a WIM-based payload (.wim + .psf).
                # Server 2022 and earlier use a single large CAB payload.
                Write-Host "  Inspecting MSU contents..."
                $listing = & expand -d "$pkgPath" 2>&1
                Write-Host ($listing | Out-String)

                $hasWimPayload = $listing | Where-Object { $_ -match '\.wim' }

                if ($hasWimPayload) {
                    # New WIM-based MSU format (Server 2025 / Win11 24H2).
                    # The update payload is a WIM + PSF, not an extractable CAB.
                    # DISM handles this natively when host and image versions match.
                    Write-Host "  Detected WIM-based MSU (new format) - applying directly with DISM..."
                    dism /Image:$MountWIM /Add-Package /PackagePath:"$pkgPath"
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "[WARNING] DISM returned exit code $LASTEXITCODE for $($u.Name)"
                    } else {
                        Write-Host "[OK] Successfully injected $($u.Name)"
                    }
                    Remove-Item "$pkgPath" -Force
                } else {
                    # Classic CAB-based MSU format (Server 2022 and earlier).
                    # Extract the payload CAB and apply it directly to avoid
                    # 0x800f0823 errors from host/image DISM version mismatch.
                    $msuTemp = "$env:TEMP\msu_extract"
                    if (Test-Path $msuTemp) { Remove-Item $msuTemp -Recurse -Force }
                    New-Item $msuTemp -ItemType Directory -Force | Out-Null

                    Write-Host "  Extracting CABs from MSU (classic format)..."
                    $expandOut = & expand -f:*.cab "$pkgPath" $msuTemp 2>&1
                    Write-Host "  expand exit code: $LASTEXITCODE"

                    $cabs = @(Get-ChildItem $msuTemp -Filter '*.cab' |
                              Where-Object { $_.Name -notmatch 'WSUSSCAN' })

                    Write-Host "  Payload CABs found: $($cabs.Count)"
                    foreach ($cab in $cabs) {
                        Write-Host "    $($cab.Name) ($([math]::Round($cab.Length/1MB,1)) MB)"
                    }

                    if ($cabs.Count -gt 0) {
                        foreach ($cab in $cabs) {
                            $cabPath = $cab.FullName
                            Write-Host "  Applying CAB: $($cab.Name)"
                            dism /Image:$MountWIM /Add-Package /PackagePath:"$cabPath"
                            if ($LASTEXITCODE -ne 0) {
                                Write-Host "[WARNING] DISM returned exit code $LASTEXITCODE for $($cab.Name)"
                            } else {
                                Write-Host "[OK] Successfully injected $($cab.Name)"
                            }
                        }
                    } else {
                        Write-Host "  [WARNING] No payload CABs found - applying MSU directly..."
                        dism /Image:$MountWIM /Add-Package /PackagePath:"$pkgPath"
                        if ($LASTEXITCODE -ne 0) {
                            Write-Host "[WARNING] DISM returned exit code $LASTEXITCODE for $($u.Name)"
                        } else {
                            Write-Host "[OK] Successfully injected $($u.Name)"
                        }
                    }

                    Remove-Item $msuTemp -Recurse -Force
                    Remove-Item "$pkgPath" -Force
                }
            } else {
                # CAB files can be applied directly
                Write-Host "  Applying CAB: $($u.Name)"
                dism /Image:$MountWIM /Add-Package /PackagePath:"$pkgPath"
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "[WARNING] DISM returned exit code $LASTEXITCODE for $($u.Name)"
                } else {
                    Write-Host "[OK] Successfully injected $($u.Name)"
                }
            }
        }
    } else {
        Write-Host "[WARNING] Updates directory exists but contains no .msu or .cab files"
        Write-Host "[WARNING] Check that Auto-Update-MSUs.ps1 downloaded updates successfully"
    }
}
else {
    Write-Host "[FAIL] Updates directory not found at $UpdatesPath"
    exit 1
}

# ===============================
# 6. Load Offline Registry
# ===============================
Write-Host "[6] Loading offline registry..."

reg load HKLM\OFFSOFT "$MountWIM\Windows\System32\Config\SOFTWARE" | Out-Null
reg load HKLM\OFFSYS  "$MountWIM\Windows\System32\Config\SYSTEM"   | Out-Null
reg load HKLM\OFFSEC  "$MountWIM\Windows\System32\Config\SECURITY" | Out-Null
reg load HKLM\OFFSAM  "$MountWIM\Windows\System32\Config\SAM"      | Out-Null

# =====================================
# 7. Apply CIS GPO: GroupPolicy + ADMX
# =====================================
Write-Host "[7] Injecting CIS GPO baseline..."

# WIM-mounted files are owned by TrustedInstaller with restrictive ACLs.
# Take ownership and grant full control so we can overwrite them.
if (Test-Path "$MountWIM\Windows\System32\GroupPolicy") {
    takeown /F "$MountWIM\Windows\System32\GroupPolicy" /R /A /D Y | Out-Null
    icacls "$MountWIM\Windows\System32\GroupPolicy" /grant Administrators:F /T /Q | Out-Null
}
if (Test-Path "$MountWIM\Windows\PolicyDefinitions") {
    takeown /F "$MountWIM\Windows\PolicyDefinitions" /R /A /D Y | Out-Null
    icacls "$MountWIM\Windows\PolicyDefinitions" /grant Administrators:F /T /Q | Out-Null
}

Copy-Item "$GpoPath\GroupPolicy"        "$MountWIM\Windows\System32\" -Recurse -Force
Write-Host "[OK] Copied GroupPolicy to $MountWIM\Windows\System32"
Copy-Item "$GpoPath\PolicyDefinitions" "$MountWIM\Windows\"           -Recurse -Force
Write-Host "[OK] Copied PolicyDefinitions to $MountWIM\Windows"


# =========================================================
# 8. First Boot Auditpol Restore & Apply Security Baseline
# =========================================================
Write-Host "[8] Adding SetupComplete.cmd..."

$Scripts = "$MountWIM\Windows\Setup\Scripts"
New-Item $Scripts -ItemType Directory -Force | Out-Null

Set-Content "$Scripts\SetupComplete.cmd" @"
@echo off

regedit /s "C:\Windows\Setup\Scripts\set_security_features.reg"
secedit /configure /cfg "C:\Windows\Setup\Scripts\Security.csv" /db defltbase.sdb /verbose
auditpol /restore /file:"C:\Windows\Setup\Scripts\Audit.ini"
del C:\Windows\Setup\Scripts\SetupComplete.cmd
"@

Copy-Item "$GpoPath\set_security_features.reg" "$Scripts\set_security_features.reg" -Force
Write-Host "[OK] Copied set_security_features.reg to $Scripts"
Copy-Item "$GpoPath\Security.csv" "$Scripts\Security.csv" -Force
Write-Host "[OK] Copied Security.csv to $Scripts"
Copy-Item "$GpoPath\Audit.ini" "$Scripts\Audit.ini" -Force
Write-Host "[OK] Copied Audit.ini to $Scripts"

# ===============================
# 8b. Inject Sysprep Unattend
# ===============================
if ($Timezone -and $UnattendPath) {
    Write-Host "[8b] Injecting Sysprep unattend for timezone: $Timezone"

    $unattendXml = Join-Path $UnattendPath "unattend_$Timezone.xml"
    $sysprepCmd  = Join-Path $UnattendPath "Sysprep_$Timezone.cmd"

    if (!(Test-Path $unattendXml)) {
        Write-Host "[FAIL] Unattend file not found: $unattendXml"
        exit 1
    }

    # Copy unattend.xml to Sysprep directory in the offline image
    $sysprepDir = "$MountWIM\Windows\System32\Sysprep"
    Copy-Item $unattendXml "$sysprepDir\unattend_$Timezone.xml" -Force
    Write-Host "[OK] Copied unattend_$Timezone.xml to $sysprepDir"

    # Also place it as the default unattend.xml for Windows Setup
    $pantherDir = "$MountWIM\Windows\Panther"
    New-Item $pantherDir -ItemType Directory -Force | Out-Null
    Copy-Item $unattendXml "$pantherDir\Unattend.xml" -Force
    Write-Host "[OK] Copied Unattend.xml to $pantherDir"

    # Copy the sysprep batch file if it exists
    if (Test-Path $sysprepCmd) {
        Copy-Item $sysprepCmd "$sysprepDir\Sysprep_$Timezone.cmd" -Force
        Write-Host "[OK] Copied Sysprep_$Timezone.cmd to $sysprepDir"
    }

    # NOTE: We do NOT call "dism /Apply-Unattend" here because the XML contains
    # specialize/oobeSystem pass settings (UserAccounts, AutoLogon, TimeZone) that
    # reference account names which cannot be resolved to SIDs against an offline
    # image (error 1332). Placing Unattend.xml in \Windows\Panther\ is sufficient;
    # Windows Setup discovers it automatically at first boot.
    Write-Host "[OK] Unattend will be applied by Windows Setup at first boot"
} elseif ($Timezone) {
    Write-Host "[9b] Skipping unattend injection - no UnattendPath provided"
} else {
    Write-Host "[9b] Skipping unattend injection - no Timezone specified"
}

# ===============================
# 9. Cleanup Offline Registry
# ===============================
Write-Host "[9] Unloading registry hives..."

reg unload HKLM\OFFSOFT | Out-Null
reg unload HKLM\OFFSYS  | Out-Null
reg unload HKLM\OFFSEC  | Out-Null
reg unload HKLM\OFFSAM  | Out-Null

# ===============================
# 10. Commit WIM
# ===============================
$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
Write-Host "[10] Committing WIM... (Free disk: ${freeGB} GB)"
dism /Unmount-WIM /MountDir:$MountWIM /Commit

if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] DISM commit failed with exit code $LASTEXITCODE"
    exit 1
}

$wimSize = [math]::Round((Get-Item $WIM).Length / 1GB, 2)
Write-Host "[OK] WIM committed ($wimSize GB)"

# ===============================
# 11. Build Hardened ISO
# ===============================
$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
Write-Host "[11] Building final ISO... (Free disk: ${freeGB} GB)"

$Oscd = "C:\ADKTools\Oscdimg\oscdimg.exe"
$AdkDir = Split-Path $Oscd -Parent

# Prefer the ADK's own boot sector files over the ISO-extracted copies.
# The ADK files are the canonical versions designed for use with oscdimg
# and haven't been through filesystem extraction that could alter them.
$AdkBios = Join-Path $AdkDir "etfsboot.com"
$AdkUefi = Join-Path $AdkDir "efisys_noprompt.bin"

if ((Test-Path $AdkBios) -and (Test-Path $AdkUefi)) {
    $BiosBoot = $AdkBios
    $UefiBoot = $AdkUefi
    Write-Host "Using ADK boot sector files:"
} else {
    $BiosBoot = "$Extract\boot\etfsboot.com"
    $UefiBoot = "$Extract\efi\microsoft\boot\efisys_noprompt.bin"
    Write-Host "ADK boot files not found, using ISO-extracted boot sector files:"
}
Write-Host "  BIOS: $BiosBoot"
Write-Host "  UEFI: $UefiBoot"

# The BCD store MUST exist on the ISO filesystem for the boot manager
$BcdFile = "$Extract\efi\microsoft\boot\BCD"

# Verify all boot-critical files and compare hashes with post-extraction baseline
Write-Host "Pre-build boot file verification..."
$bootFail = $false
foreach ($bf in @(
    @{ Path = $BiosBoot; Desc = "BIOS boot sector" },
    @{ Path = $UefiBoot; Desc = "UEFI boot sector" },
    @{ Path = $BcdFile;  Desc = "UEFI BCD store" }
)) {
    if (!(Test-Path $bf.Path)) {
        Write-Host "  [FAIL] Missing $($bf.Desc): $($bf.Path)"
        $bootFail = $true
    } else {
        $fi = Get-Item $bf.Path
        $hash = (Get-FileHash $bf.Path -Algorithm SHA256).Hash
        if ($fi.Length -eq 0) {
            Write-Host "  [FAIL] Empty $($bf.Desc): $($bf.Path) (0 bytes)"
            $bootFail = $true
        } else {
            Write-Host "  [OK] $($bf.Desc): $($bf.Path) ($($fi.Length) bytes) SHA256=$hash"
        }
        # Compare ISO-extracted files against post-extraction baseline
        if ($bootFileHashes.ContainsKey($bf.Path)) {
            if ($bootFileHashes[$bf.Path] -ne $hash) {
                Write-Host "  [WARNING] Hash changed since extraction! Was: $($bootFileHashes[$bf.Path])"
            } else {
                Write-Host "  [OK] Hash matches post-extraction baseline"
            }
        }
    }
}
if ($bootFail) { throw "Boot-critical files are missing or corrupt - aborting ISO build" }

# Build oscdimg arguments using splatting to avoid PowerShell
# argument-parsing issues with the complex -bootdata string.
$bootdataArg = "-bootdata:2#p0,e,b${BiosBoot}#pEF,e,b${UefiBoot}"
$oscdArgs = @('-m', '-o', '-u2', '-udfver102', $bootdataArg, $Extract, $OutputIso)

Write-Host "oscdimg command:"
Write-Host "  $Oscd"
foreach ($a in $oscdArgs) { Write-Host "    $a" }

& $Oscd @oscdArgs

if ($LASTEXITCODE -ne 0) {
    throw "oscdimg failed with exit code $LASTEXITCODE"
}

$isoSize = [math]::Round((Get-Item $OutputIso).Length / 1GB, 2)
Write-Host "==============================================="
Write-Host " [OK] Hardened image built ($isoSize GB):"
Write-Host "     $OutputIso"
Write-Host "==============================================="