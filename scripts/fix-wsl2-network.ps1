# PowerShell script to fix WSL2 network performance issues
# Run this in Windows PowerShell as Administrator

Write-Host "Fixing WSL2 Network Performance Issues..." -ForegroundColor Green

# 1. Disable Large Send Offload on WSL vEthernet adapter
Write-Host "`n1. Disabling Large Send Offload..." -ForegroundColor Yellow
Get-NetAdapter | Where-Object {$_.InterfaceDescription -Match "Hyper-V Virtual Ethernet Adapter" -and $_.Name -Match "WSL"} | ForEach-Object {
    Write-Host "   Configuring adapter: $($_.Name)"
    Disable-NetAdapterLso -Name $_.Name -IPv4 -IPv6
    Set-NetAdapterAdvancedProperty -Name $_.Name -DisplayName "Large Send Offload V2 (IPv4)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name $_.Name -DisplayName "Large Send Offload V2 (IPv6)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue
}

# 2. Disable Large Send Offload on Docker adapters
Write-Host "`n2. Disabling Large Send Offload on Docker adapters..." -ForegroundColor Yellow
Get-NetAdapter | Where-Object {$_.Name -Match "vEthernet \(DockerNAT\)" -or $_.Name -Match "vEthernet \(Default Switch\)"} | ForEach-Object {
    Write-Host "   Configuring adapter: $($_.Name)"
    Disable-NetAdapterLso -Name $_.Name -IPv4 -IPv6 -ErrorAction SilentlyContinue
}

# 3. Set TCP settings for better performance
Write-Host "`n3. Optimizing TCP settings..." -ForegroundColor Yellow
netsh int tcp set global chimney=disabled
netsh int tcp set global rss=enabled
netsh int tcp set global netdma=disabled
netsh int tcp set global autotuninglevel=normal

# 4. Restart WSL
Write-Host "`n4. Restarting WSL..." -ForegroundColor Yellow
wsl --shutdown
Start-Sleep -Seconds 2

Write-Host "`nNetwork optimizations complete!" -ForegroundColor Green
Write-Host "Please restart Docker Desktop for all changes to take effect." -ForegroundColor Cyan