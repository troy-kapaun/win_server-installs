if (!(Get-Module MSCatalogLTS -ListAvailable)) {
    Install-Module MSCatalogLTS -Scope CurrentUser -Force
}

$Paths = @{
    "Windows Server 2022" = "C:\WIMBUILD\updates\2022"
    "Windows Server 2025" = "C:\WIMBUILD\updates\2025"
}

foreach ($Product in $Paths.Keys) {
    Write-Host "Searching updates for $Product..."
    
    $updates = Get-MSCatalogUpdate -Search "$Product x64" |
               Where-Object { $_.Title -match "Cumulative Update" } |
               Sort-Object LastUpdated -Descending |
               Select-Object -First 1

    $Dest = $Paths[$Product]
    if (!(Test-Path $Dest)) { New-Item $Dest -ItemType Directory -Force | Out-Null }

    Write-Host "Downloading $($updates.Title)..."
    $updates | Save-MSCatalogUpdate -Destination $Dest
}