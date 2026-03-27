Write-Host "=== CLEANUP WIM MOUNTS ==="

$mounts = dism /Get-MountStatus | Select-String "Mounted"
foreach ($m in $mounts) {
    $dir = ($m -split ": ")[1]
    dism /Unmount-WIM /MountDir:$dir /Discard
}

if (Test-Path "C:\WIMBUILD\Work") {
    Remove-Item "C:\WIMBUILD\Work" -Recurse -Force
}

Write-Host "✅ Cleanup complete"