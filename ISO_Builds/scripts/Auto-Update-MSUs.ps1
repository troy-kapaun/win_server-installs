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

foreach ($ver in $Versions) {
    $releaseId = $VersionMap[$ver].ReleaseId
    $Dest      = $VersionMap[$ver].Dest

    # Search using the catalog naming convention:
    #   "YYYY-MM Microsoft server operating system-21H2"  (Server 2022)
    #   "YYYY-MM Microsoft server operating system-24H2"  (Server 2025)
    $search = "$YearMonth Microsoft server operating system-$releaseId"
    Write-Host "Searching: $search"

    $updates = Get-MSCatalogUpdate -Search $search |
               Where-Object { $_.Title -match 'Cumulative Update' -and $_.Title -match 'x64' } |
               Sort-Object LastUpdated -Descending |
               Select-Object -First 1

    # If the current month has no CU yet, fall back to the previous month
    if (!$updates) {
        $prevMonth = (Get-Date).AddMonths(-1).ToString('yyyy-MM')
        $search = "$prevMonth Microsoft server operating system-$releaseId"
        Write-Host "[INFO] No CU for $YearMonth, trying previous month: $search"

        $updates = Get-MSCatalogUpdate -Search $search |
                   Where-Object { $_.Title -match 'Cumulative Update' -and $_.Title -match 'x64' } |
                   Sort-Object LastUpdated -Descending |
                   Select-Object -First 1
    }

    if (!$updates) {
        Write-Host "[WARNING] No cumulative update found for Server $ver ($releaseId)"
        continue
    }

    if (!(Test-Path $Dest)) { New-Item $Dest -ItemType Directory -Force | Out-Null }

    Write-Host "Downloading $($updates.Title)..."
    $updates | Save-MSCatalogUpdate -Destination $Dest

    $msu = Get-ChildItem $Dest -Filter '*.msu' | Select-Object -First 1
    if ($msu) {
        Write-Host "[OK] Saved: $($msu.Name) ($([math]::Round($msu.Length/1MB,1)) MB)"
    } else {
        Write-Host "[WARNING] No .msu file found in $Dest after download"
    }
}