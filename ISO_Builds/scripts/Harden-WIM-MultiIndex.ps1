param(
    [string]$IsoPath,
    [string]$UpdatesPath,
    [string]$GpoPath,
    [string]$OutputFolder = "C:\WIMBUILD"
)

$Base = "C:\WIMBUILD\Work-Multi"
Remove-Item $Base -Recurse -Force -ErrorAction SilentlyContinue
New-Item $Base -ItemType Directory | Out-Null

$MountISO = "$Base\ISO_MOUNT"
$Extract  = "$Base\ISO_EXTRACT"
$MountWIM = "$Base\WIM_MOUNT"
New-Item $MountISO,$Extract,$MountWIM -ItemType Directory -Force | Out-Null

Copy-Item $IsoPath "$Base\input.iso" -Force

$IsoObj = Mount-DiskImage -ImagePath "$Base\input.iso" -PassThru
$Drive  = ($IsoObj | Get-Volume).DriveLetter + ":"

robocopy "$Drive\" $Extract /MIR | Out-Null

$WIM = "$Extract\sources\install.wim"

# Get all indexes
$indexes = (dism /Get-WimInfo /WimFile:$WIM | Select-String "Index : ").ToString().Split(":")[1].Trim()

foreach ($idx in $indexes) {
    Write-Host "Hardening Index $idx"

    dism /Mount-WIM /WimFile:$WIM /Index:$idx /MountDir:$MountWIM

    foreach ($u in Get-ChildItem $UpdatesPath -Filter *.msu) {
        dism /Image:$MountWIM /Add-Package /PackagePath:$u.FullName
    }

    $Scripts = "$MountWIM\Windows\Setup\Scripts"
    New-Item $Scripts -ItemType Directory -Force | Out-Null
    Copy-Item "$GpoPath\Audit.ini" "$Scripts\Audit.ini" -Force
    Set-Content "$Scripts\SetupComplete.cmd" '@
auditpol /restore /file:"C:\Windows\Setup\Scripts\Audit.ini"
del C:\Windows\Setup\Scripts\SetupComplete.cmd
@'

    dism /Unmount-WIM /MountDir:$MountWIM /Commit

    $OutISO = "$OutputFolder\Hardened-Index$idx.iso"
    $Oscd = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    & $Oscd -m -o -u2 -udfver102 $Extract $OutISO
}

Write-Host "✅ Multi-index processing complete."