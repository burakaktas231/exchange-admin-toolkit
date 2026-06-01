<#
.SYNOPSIS
    Exchange Toplantı Odası ve Kaynak Mailbox Yönetimi
.DESCRIPTION
    Toplantı odası mailbox'larını oluşturur ve yönetir:
    - Oda mailbox oluşturma (Room Mailbox)
    - Ekipman mailbox oluşturma (Equipment Mailbox)
    - Otomatik kabul politikası ayarlama
    - Rezervasyon raporu
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.NOTES
    Exchange Management Shell gerektirir.
.EXAMPLE
    .\Manage-RoomMailbox.ps1 -Action CreateRoom -Name "Toplanti Odasi 1" -Email "toplanti1@aschukuk.com" -Capacity 12
    .\Manage-RoomMailbox.ps1 -Action ListRooms
    .\Manage-RoomMailbox.ps1 -Action BookingReport -RoomName "Toplanti Odasi 1" -Days 30
#>

param(
    [ValidateSet("CreateRoom", "CreateEquipment", "ListRooms", "ConfigureAutoAccept", "BookingReport", "SetWorkingHours")]
    [string]$Action = "ListRooms",

    [string]$Name,
    [string]$Email,
    [int]$Capacity,
    [string]$RoomName,
    [int]$Days = 30
)

Write-Host "`n=== TOPLANTI ODASI & KAYNAK YÖNETİMİ ===" -ForegroundColor Cyan
Write-Host "İşlem: $Action"
Write-Host "Tarih: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

switch ($Action) {

    # ============================================
    # TOPLANTI ODASI OLUŞTUR
    # ============================================
    "CreateRoom" {
        if (-not $Name -or -not $Email) {
            Write-Host "Kullanım: -Action CreateRoom -Name 'Oda Adı' -Email 'oda@domain.com' -Capacity 10" -ForegroundColor Yellow
            exit
        }

        try {
            New-Mailbox -Name $Name `
                        -DisplayName $Name `
                        -PrimarySmtpAddress $Email `
                        -Room

            # Kapasiteyi ayarla
            if ($Capacity) {
                Set-Place -Identity $Name -Capacity $Capacity
            }

            # Otomatik kabul aç
            Set-CalendarProcessing -Identity $Name `
                -AutomateProcessing AutoAccept `
                -DeleteComments $false `
                -AddOrganizerToSubject $true `
                -RemovePrivateProperty $false

            Write-Host "[OK] Toplantı odası oluşturuldu:" -ForegroundColor Green
            Write-Host "     İsim     : $Name"
            Write-Host "     Email    : $Email"
            Write-Host "     Kapasite : $Capacity kişi"
            Write-Host "     Otomatik kabul: Açık"
        }
        catch {
            Write-Host "[HATA] Oda oluşturulamadı: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # EKİPMAN MAILBOX OLUŞTUR
    # ============================================
    "CreateEquipment" {
        if (-not $Name -or -not $Email) {
            Write-Host "Kullanım: -Action CreateEquipment -Name 'Projeksiyon 1' -Email 'proj1@domain.com'" -ForegroundColor Yellow
            exit
        }

        try {
            New-Mailbox -Name $Name `
                        -DisplayName $Name `
                        -PrimarySmtpAddress $Email `
                        -Equipment

            Set-CalendarProcessing -Identity $Name -AutomateProcessing AutoAccept

            Write-Host "[OK] Ekipman mailbox'ı oluşturuldu:" -ForegroundColor Green
            Write-Host "     İsim  : $Name"
            Write-Host "     Email : $Email"
        }
        catch {
            Write-Host "[HATA] Ekipman oluşturulamadı: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # TÜM ODALARI LİSTELE
    # ============================================
    "ListRooms" {
        Write-Host "--- Toplantı Odaları ---`n" -ForegroundColor Cyan

        $Rooms = Get-Mailbox -RecipientTypeDetails RoomMailbox -ResultSize Unlimited

        if ($Rooms) {
            foreach ($Room in $Rooms) {
                $CalConfig = Get-CalendarProcessing -Identity $Room.Identity
                $PlaceInfo = Get-Place -Identity $Room.Identity -ErrorAction SilentlyContinue

                $AutoAccept = if ($CalConfig.AutomateProcessing -eq "AutoAccept") { "Otomatik Kabul" } else { "Manuel" }
                $Cap = if ($PlaceInfo.Capacity) { "$($PlaceInfo.Capacity) kişi" } else { "Belirtilmemiş" }

                Write-Host "$($Room.DisplayName)" -ForegroundColor White
                Write-Host "  Email    : $($Room.PrimarySmtpAddress)"
                Write-Host "  Kapasite : $Cap"
                Write-Host "  Politika : $AutoAccept"

                # Delegeler
                if ($CalConfig.ResourceDelegates) {
                    Write-Host "  Delegeler: $($CalConfig.ResourceDelegates -join ', ')" -ForegroundColor DarkCyan
                }
                Write-Host ""
            }
            Write-Host "Toplam oda: $($Rooms.Count)"
        }

        Write-Host "`n--- Ekipmanlar ---`n" -ForegroundColor Cyan

        $Equipment = Get-Mailbox -RecipientTypeDetails EquipmentMailbox -ResultSize Unlimited
        if ($Equipment) {
            foreach ($Eq in $Equipment) {
                Write-Host "$($Eq.DisplayName) - $($Eq.PrimarySmtpAddress)"
            }
            Write-Host "`nToplam ekipman: $($Equipment.Count)"
        }
        else {
            Write-Host "Tanımlı ekipman yok."
        }
    }

    # ============================================
    # OTOMATİK KABUL AYARLARI
    # ============================================
    "ConfigureAutoAccept" {
        if (-not $RoomName) {
            Write-Host "Kullanım: -Action ConfigureAutoAccept -RoomName 'Oda Adı'" -ForegroundColor Yellow
            exit
        }

        try {
            Set-CalendarProcessing -Identity $RoomName `
                -AutomateProcessing AutoAccept `
                -AllBookInPolicy $true `
                -DeleteComments $false `
                -AddOrganizerToSubject $true `
                -AllowConflicts $false `
                -BookingWindowInDays 180 `
                -MaximumDurationInMinutes 480 `
                -EnforceSchedulingHorizon $true

            Write-Host "[OK] $RoomName otomatik kabul ayarları güncellendi:" -ForegroundColor Green
            Write-Host "     Otomatik Kabul : Açık"
            Write-Host "     Çakışma İzni   : Kapalı"
            Write-Host "     Max Süre       : 8 saat"
            Write-Host "     Rezervasyon    : 180 gün ileriye kadar"
        }
        catch {
            Write-Host "[HATA] Ayar güncellenemedi: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # REZERVASYON RAPORU
    # ============================================
    "BookingReport" {
        if (-not $RoomName) {
            Write-Host "Kullanım: -Action BookingReport -RoomName 'Oda Adı' -Days 30" -ForegroundColor Yellow
            exit
        }

        Write-Host "--- $RoomName Rezervasyon Raporu (Son $Days gün) ---`n" -ForegroundColor Cyan

        try {
            $StartDate = (Get-Date).AddDays(-$Days)
            $EndDate   = Get-Date

            $Bookings = Get-CalendarDiagnosticLog -Identity $RoomName `
                -StartDate $StartDate -EndDate $EndDate `
                -ResultSize 500 -ErrorAction Stop |
            Where-Object { $_.CalendarLogTriggerAction -eq "Create" }

            if ($Bookings) {
                $Bookings | Group-Object { $_.OriginalLastModifiedTime.DayOfWeek } |
                    Sort-Object Count -Descending | ForEach-Object {
                        Write-Host ("  {0,-12} : {1} toplantı" -f $_.Name, $_.Count)
                    }

                Write-Host "`nToplam: $($Bookings.Count) rezervasyon"
                Write-Host "Günlük ortalama: $([math]::Round($Bookings.Count / $Days, 1))"
            }
            else {
                Write-Host "Bu dönemde rezervasyon bulunamadı."
            }
        }
        catch {
            Write-Host "[BİLGİ] Rezervasyon logu alınamadı: $_" -ForegroundColor Yellow
            Write-Host "Alternatif: Outlook'tan oda takvimini açarak kontrol edebilirsiniz."
        }
    }
}
