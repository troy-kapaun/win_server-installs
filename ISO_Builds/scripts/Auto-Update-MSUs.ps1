param(
    [ValidateSet('2022','2025')]
    [string]$Version
)

if (!(Get-Module MSCatalogLTS -ListAvailable)) {
    Install-Module MSCatalogLTS -Scope CurrentUser -Force
}

# Map server version to OS release ID used by Microsoft Update Catalog
$VersionMap = @{
    '2022' = @{ ReleaseId = '21H2'; Dest = 'C:\WIMBUILD\updates\2022' }
    '2025' = @{ ReleaseId = '24H2'; Dest = 'C:\WIMBUILD\updates\2025' }
}

# When a specific version is requested, only process that version
$Versions = if ($Version) { @($Version) } else { @('2022','2025') }

$YearMonth = (Get-Date).ToString('yyyy-MM')
$PrevMonth = (Get-Date).AddMonths(-1).ToString('yyyy-MM')

foreach ($ver in $Versions) {
    $releaseId = $VersionMap[$ver].ReleaseId
    $Dest      = $VersionMap[$ver].Dest

    if (!(Test-Path $Dest)) { New-Item $Dest -ItemType Directory -Force | Out-Null }

    # ---- 1. OS Cumulative Update ----
    Write-Host "`n=== OS Cumulative Update for Server $ver ($releaseId) ==="

    $osCU = $null
    foreach ($month in @($YearMonth, $PrevMonth)) {
        $search = "$month Cumulative Update for Microsoft server operating system version $releaseId x64"
        Write-Host "Searching: $search"
        $raw = Get-MSCatalogUpdate -Search $search
        Write-Host "  Raw results: $(@($raw).Count) entries"
        $raw | Select-Object -First 5 | ForEach-Object { Write-Host "    - $($_.Title)" }

        $osCU = $raw |
                Where-Object { $_.Title -match 'Cumulative Update' -and
                               $_.Title -notmatch '\.NET' -and
                               $_.Title -match 'x64' } |
                Sort-Object LastUpdated -Descending |
                Select-Object -First 1
        if ($osCU) { break }
    }

    if ($osCU) {
        Write-Host "Downloading: $($osCU.Title)"
        $osCU | Save-MSCatalogUpdate -Destination $Dest
    } else {
        Write-Host "[WARNING] No OS cumulative update found for Server $ver ($releaseId)"
    }

    # ---- 2. .NET Framework Cumulative Update ----
    Write-Host "`n=== .NET Framework CU for Server $ver ($releaseId) ==="

    $dotnetCU = $null
    foreach ($month in @($YearMonth, $PrevMonth)) {
        $search = "$month Cumulative Update .NET Framework Microsoft server operating system $releaseId x64"
        Write-Host "Searching: $search"
        $raw = Get-MSCatalogUpdate -Search $search
        Write-Host "  Raw results: $(@($raw).Count) entries"
        $raw | Select-Object -First 5 | ForEach-Object { Write-Host "    - $($_.Title)" }

        $dotnetCU = $raw |
                    Where-Object { $_.Title -match '\.NET Framework' -and
                                   $_.Title -match 'x64' -and
                                   $_.Title -match $releaseId } |
                    Sort-Object LastUpdated -Descending |
                    Select-Object -First 1
        if ($dotnetCU) { break }
    }

    # .NET CUs are sometimes published less frequently; try without month prefix
    if (!$dotnetCU) {
        $search = "Cumulative Update .NET Framework Microsoft server operating system $releaseId x64"
        Write-Host "Searching (any month): $search"
        $raw = Get-MSCatalogUpdate -Search $search
        Write-Host "  Raw results: $(@($raw).Count) entries"
        $raw | Select-Object -First 5 | ForEach-Object { Write-Host "    - $($_.Title)" }

        $dotnetCU = $raw |
                    Where-Object { $_.Title -match '\.NET Framework' -and
                                   $_.Title -match 'x64' -and
                                   $_.Title -match $releaseId } |
                    Sort-Object LastUpdated -Descending |
                    Select-Object -First 1
    }

    if ($dotnetCU) {
        Write-Host "Downloading: $($dotnetCU.Title)"
        $dotnetCU | Save-MSCatalogUpdate -Destination $Dest
    } else {
        Write-Host "[WARNING] No .NET Framework CU found for Server $ver ($releaseId)"
    }

    # ---- Summary ----
    Write-Host "`n=== Downloaded updates for Server $ver ==="
    $files = Get-ChildItem $Dest -Include '*.msu','*.cab' -Recurse
    if ($files) {
        foreach ($f in $files) {
            Write-Host "[OK] $($f.Name) ($([math]::Round($f.Length/1MB,1)) MB)"
        }
    } else {
        Write-Host "[WARNING] No update files (.msu or .cab) found in $Dest"
    }
}