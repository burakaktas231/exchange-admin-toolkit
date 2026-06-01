<#
.SYNOPSIS
    Exchange Mobil Cihaz (ActiveSync) Yönetimi
.DESCRIPTION
    Exchange'e bağlı mobil cihazları listeler ve yönetir:
    - Kullanıcıya göre cihaz listesi
    - Eski/inaktif cihaz tespiti
    - Uzaktan cihaz silme (Remote Wipe)
    - ActiveSync politika kontrolü
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.NOTES
    Exchange Management Shell gerektirir.
.EXAMPLE
    .\Manage-MobileDevices.ps1 -Action List
    .\Manage-MobileDevices.ps1 -Action UserDevices -UserName "mehmet.yilmaz"
    .\Manage-MobileDevices.ps1 -Action Stale -InactiveDays 90
    .\Manage-MobileDevices.ps1 -Action Wipe -UserName "eski.calisan" -DeviceID "ABCD1234"
#>

param(
    [ValidateSet("List", "UserDevices", "Stale", "Wipe", "PolicyCheck")]
    [string]$Action = "List",

    [string]$UserName,
    [string]$DeviceID,
    [int]$InactiveDays = 90,
    [switch]$ExportCSV
)

Write-Host "`n=== MOBİL CİHAZ (ACTIVESYNC) YÖNETİMİ ===" -ForegroundColor Cyan
Write-Host "İşlem: $Action"
Write-Host "Tarih: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

switch ($Action) {

    # ============================================
    # TÜM CİHAZLARI LİSTELE
    # ============================================
    "List" {
        $AllDevices = @()

        $Mailboxes = Get-CASMailbox -ResultSize Unlimited |
            Where-Object { $_.HasActiveSyncDevicePartnership -eq $true }

        Write-Host "ActiveSync kullanıcı sayısı: $($Mailboxes.Count)`n"

        foreach ($MB in $Mailboxes) {
            try {
                $Devices = Get-MobileDeviceStatistics -Mailbox $MB.Identity -ErrorAction SilentlyContinue

                foreach ($Dev in $Devices) {
                    $AllDevices += [PSCustomObject]@{
                        Kullanici       = $MB.DisplayName
                        SamAccount      = $MB.SamAccountName
                        CihazModeli     = $Dev.DeviceModel
                        CihazTipi       = $Dev.DeviceType
                        CihazOS         = $Dev.DeviceOS
                        SonSync         = $Dev.LastSuccessSync
                        Durum           = $Dev.Status
                        DeviceID        = $Dev.DeviceID
                    }
                }
            }
            catch { }
        }

        # Göster
        $AllDevices | Sort-Object SonSync -Descending |
            Format-Table Kullanici, CihazModeli, CihazOS, SonSync, Durum -AutoSize

        Write-Host "Toplam cihaz: $($AllDevices.Count)"

        # Cihaz tipi dağılımı
        Write-Host "`nCihaz Dağılımı:" -ForegroundColor Cyan
        $AllDevices | Group-Object CihazTipi | Sort-Object Count -Descending |
            ForEach-Object { Write-Host ("  {0,-20} : {1}" -f $_.Name, $_.Count) }

        if ($ExportCSV) {
            $ReportPath = "$PSScriptRoot\MobileDevices_$(Get-Date -Format 'yyyy-MM-dd').csv"
            $AllDevices | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
            Write-Host "`nRapor kaydedildi: $ReportPath" -ForegroundColor Green
        }
    }

    # ============================================
    # KULLANICI CİHAZLARI
    # ============================================
    "UserDevices" {
        if (-not $UserName) {
            Write-Host "Kullanım: -Action UserDevices -UserName 'mehmet.yilmaz'" -ForegroundColor Yellow
            exit
        }

        try {
            $Devices = Get-MobileDeviceStatistics -Mailbox $UserName

            if ($Devices) {
                Write-Host "$UserName - Bağlı Cihazlar:`n" -ForegroundColor White

                foreach ($Dev in $Devices) {
                    $SyncAge = if ($Dev.LastSuccessSync) {
                        ((Get-Date) - $Dev.LastSuccessSync).Days
                    } else { "N/A" }

                    $Color = if ($SyncAge -ne "N/A" -and $SyncAge -gt 30) { "Yellow" } else { "Green" }

                    Write-Host "  Cihaz    : $($Dev.DeviceModel) ($($Dev.DeviceType))" -ForegroundColor $Color
                    Write-Host "  OS       : $($Dev.DeviceOS)"
                    Write-Host "  Son Sync : $($Dev.LastSuccessSync) ($SyncAge gün önce)"
                    Write-Host "  Durum    : $($Dev.Status)"
                    Write-Host "  DeviceID : $($Dev.DeviceID)"
                    Write-Host "  ---"
                }
            }
            else {
                Write-Host "$UserName için bağlı cihaz bulunamadı." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "[HATA] Cihaz bilgisi alınamadı: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # ESKİ/İNAKTİF CİHAZLAR
    # ============================================
    "Stale" {
        Write-Host "$InactiveDays+ gündür senkronize olmayan cihazlar:`n" -ForegroundColor Yellow

        $CutoffDate = (Get-Date).AddDays(-$InactiveDays)
        $StaleDevices = @()

        $Mailboxes = Get-CASMailbox -ResultSize Unlimited |
            Where-Object { $_.HasActiveSyncDevicePartnership -eq $true }

        foreach ($MB in $Mailboxes) {
            try {
                $Devices = Get-MobileDeviceStatistics -Mailbox $MB.Identity -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.LastSuccessSync -and $_.LastSuccessSync -lt $CutoffDate
                    }

                foreach ($Dev in $Devices) {
                    $DaysInactive = ((Get-Date) - $Dev.LastSuccessSync).Days
                    $StaleDevices += [PSCustomObject]@{
                        Kullanici  = $MB.DisplayName
                        Cihaz      = $Dev.DeviceModel
                        SonSync    = $Dev.LastSuccessSync
                        InaktifGun = $DaysInactive
                        DeviceID   = $Dev.DeviceID
                    }

                    Write-Host ("{0,-25} {1,-20} Son sync: {2} ({3} gün)" -f `
                        $MB.DisplayName, $Dev.DeviceModel, $Dev.LastSuccessSync.ToString('dd.MM.yyyy'), $DaysInactive) `
                        -ForegroundColor Yellow
                }
            }
            catch { }
        }

        Write-Host "`nToplam eski cihaz: $($StaleDevices.Count)"
        Write-Host "[İPUCU] Temizlemek için: -Action Wipe -UserName 'x' -DeviceID 'y'" -ForegroundColor Cyan
    }

    # ============================================
    # UZAKTAN CİHAZ SİLME
    # ============================================
    "Wipe" {
        if (-not $UserName -or -not $DeviceID) {
            Write-Host "Kullanım: -Action Wipe -UserName 'kullanıcı' -DeviceID 'CihazID'" -ForegroundColor Yellow
            Write-Host "Cihaz ID'lerini görmek için: -Action UserDevices -UserName 'kullanıcı'"
            exit
        }

        Write-Host "[UYARI] Bu işlem cihazı fabrika ayarlarına sıfırlar!" -ForegroundColor Red
        $Confirm = Read-Host "Devam etmek istiyor musunuz? (EVET yazın)"

        if ($Confirm -eq "EVET") {
            try {
                Clear-MobileDevice -Identity $DeviceID -AccountOnly:$false -Confirm:$false
                Write-Host "[OK] Remote wipe komutu gönderildi." -ForegroundColor Green
                Write-Host "     Cihaz: $DeviceID"
                Write-Host "     Kullanıcı: $UserName"
                Write-Host "     Cihaz bir sonraki senkronizasyonda silinecek."
            }
            catch {
                Write-Host "[HATA] Wipe komutu gönderilemedi: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "İşlem iptal edildi." -ForegroundColor Yellow
        }
    }

    # ============================================
    # ACTIVESYNC POLİTİKA KONTROLÜ
    # ============================================
    "PolicyCheck" {
        Write-Host "--- ActiveSync Politikaları ---`n" -ForegroundColor Cyan

        $Policies = Get-MobileDeviceMailboxPolicy

        foreach ($Pol in $Policies) {
            Write-Host "$($Pol.Name)" -ForegroundColor White
            Write-Host "  Şifre Zorunlu        : $($Pol.PasswordEnabled)"
            Write-Host "  Min. Şifre Uzunluğu  : $($Pol.MinPasswordLength)"
            Write-Host "  Basit Şifre İzni     : $($Pol.AllowSimplePassword)"
            Write-Host "  Cihaz Şifreleme      : $($Pol.RequireDeviceEncryption)"
            Write-Host "  Max. Hata Deneme     : $($Pol.MaxPasswordFailedAttempts)"
            Write-Host "  Otomatik Kilit (dk)  : $($Pol.MaxInactivityTimeLock)"
            Write-Host "  Kamera İzni          : $($Pol.AllowCamera)"
            Write-Host "  Bluetooth İzni       : $($Pol.AllowBluetooth)"
            Write-Host ""
        }

        # Politikası olmayan kullanıcılar
        $NoPolicyUsers = Get-CASMailbox -ResultSize Unlimited |
            Where-Object { $_.HasActiveSyncDevicePartnership -eq $true -and -not $_.ActiveSyncMailboxPolicy }

        if ($NoPolicyUsers) {
            Write-Host "⚠ Politikası atanmamış kullanıcılar:" -ForegroundColor Yellow
            $NoPolicyUsers | ForEach-Object {
                Write-Host "  $($_.DisplayName)" -ForegroundColor Yellow
            }
        }
    }
}
