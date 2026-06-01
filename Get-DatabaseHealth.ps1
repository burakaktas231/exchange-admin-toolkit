<#
.SYNOPSIS
    Exchange Veritabanı Sağlık Kontrolü ve Bakımı
.DESCRIPTION
    Tüm mailbox veritabanlarının durumunu kontrol eder:
    - Mount durumu, boyut, boş alan
    - Kopya (DAG) durumu
    - Beyaz alan (whitespace) miktarı
    - Log dosya birikimi
    - Mailbox dağılım dengesi
    Bakım penceresi öncesi kontrol için ideal.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.NOTES
    Exchange Management Shell gerektirir.
.EXAMPLE
    .\Get-DatabaseHealth.ps1
    .\Get-DatabaseHealth.ps1 -IncludeLogStats
#>

param(
    [switch]$IncludeLogStats     # Transaction log dosya istatistiklerini de göster
)

Write-Host "`n=== EXCHANGE VERİTABANI SAĞLIK RAPORU ===" -ForegroundColor Cyan
Write-Host "Tarih: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

# ============================================
# 1) VERİTABANI DURUMLARI
# ============================================
Write-Host "--- Veritabanı Durumları ---`n" -ForegroundColor Cyan

try {
    $Databases = Get-MailboxDatabase -Status -ErrorAction Stop

    $DBReport = @()

    foreach ($DB in $Databases) {
        # Boyut hesapla
        $SizeGB = if ($DB.DatabaseSize) {
            [math]::Round($DB.DatabaseSize.ToBytes() / 1GB, 2)
        } else { 0 }

        $WhitespaceGB = if ($DB.AvailableNewMailboxSpace) {
            [math]::Round($DB.AvailableNewMailboxSpace.ToBytes() / 1GB, 2)
        } else { 0 }

        $WhitespacePercent = if ($SizeGB -gt 0) {
            [math]::Round(($WhitespaceGB / $SizeGB) * 100, 1)
        } else { 0 }

        # Mailbox sayısı
        $MBCount = (Get-Mailbox -Database $DB.Name -ResultSize Unlimited).Count

        $DBInfo = [PSCustomObject]@{
            Veritabani      = $DB.Name
            Sunucu          = $DB.Server
            Mounted         = $DB.Mounted
            Boyut_GB        = $SizeGB
            BosAlan_GB      = $WhitespaceGB
            BosAlan_Yuzde   = $WhitespacePercent
            Mailbox_Sayisi  = $MBCount
            EDBDosyaYolu    = $DB.EdbFilePath
            LogYolu         = $DB.LogFolderPath
        }
        $DBReport += $DBInfo

        # Ekrana yaz
        $MountColor = if ($DB.Mounted) { "Green" } else { "Red" }
        $MountText  = if ($DB.Mounted) { "Mounted" } else { "DISMOUNTED!" }
        $SizeColor  = if ($WhitespacePercent -gt 30) { "Yellow" } else { "White" }

        Write-Host "$($DB.Name)" -ForegroundColor White
        Write-Host ("  Durum      : {0}" -f $MountText) -ForegroundColor $MountColor
        Write-Host ("  Boyut      : {0} GB" -f $SizeGB)
        Write-Host ("  Beyaz Alan : {0} GB (%{1})" -f $WhitespaceGB, $WhitespacePercent) -ForegroundColor $SizeColor
        Write-Host ("  Mailbox    : {0} adet" -f $MBCount)
        Write-Host ("  Sunucu     : {0}" -f $DB.Server)

        if ($WhitespacePercent -gt 30) {
            Write-Host "  [İPUCU] Beyaz alan yüksek - offline defrag düşünülebilir" -ForegroundColor Yellow
        }
        Write-Host ""
    }
}
catch {
    Write-Host "[HATA] Veritabanı bilgisi alınamadı: $_" -ForegroundColor Red
    exit 1
}

# ============================================
# 2) MAILBOX DAĞILIM DENGESİ
# ============================================
Write-Host "--- Mailbox Dağılım Dengesi ---`n" -ForegroundColor Cyan

$TotalMailboxes = ($DBReport | Measure-Object Mailbox_Sayisi -Sum).Sum
$AvgPerDB       = [math]::Round($TotalMailboxes / $DBReport.Count)

foreach ($DB in $DBReport) {
    $Deviation = $DB.Mailbox_Sayisi - $AvgPerDB
    $Bar = if ($DB.Mailbox_Sayisi -gt 0) {
        $BarLen = [math]::Min([math]::Round($DB.Mailbox_Sayisi / 2), 40)
        "█" * $BarLen
    } else { "" }

    $Color = if ([math]::Abs($Deviation) -gt ($AvgPerDB * 0.3)) { "Yellow" } else { "Green" }

    Write-Host ("{0,-20} {1,4} mailbox  {2}" -f $DB.Veritabani, $DB.Mailbox_Sayisi, $Bar) -ForegroundColor $Color
}

Write-Host "`nToplam: $TotalMailboxes mailbox | Ortalama: $AvgPerDB/DB"

# ============================================
# 3) TRANSACTION LOG İSTATİSTİKLERİ
# ============================================
if ($IncludeLogStats) {
    Write-Host "`n--- Transaction Log Dosyaları ---`n" -ForegroundColor Cyan

    foreach ($DB in $DBReport) {
        try {
            $LogPath = $DB.LogYolu.ToString()
            $LogFiles = Get-ChildItem -Path $LogPath -Filter "*.log" -ErrorAction Stop
            $LogCount = $LogFiles.Count
            $LogSizeGB = [math]::Round(($LogFiles | Measure-Object Length -Sum).Sum / 1GB, 2)

            $Color = if ($LogSizeGB -gt 10) { "Red" } elseif ($LogSizeGB -gt 5) { "Yellow" } else { "Green" }

            Write-Host ("{0,-20} : {1} dosya ({2} GB)" -f $DB.Veritabani, $LogCount, $LogSizeGB) -ForegroundColor $Color
        }
        catch {
            Write-Host ("{0,-20} : Log yoluna erişilemedi" -f $DB.Veritabani) -ForegroundColor DarkGray
        }
    }
}

# ============================================
# 4) AKTİF TAŞIMA İSTEKLERİ
# ============================================
Write-Host "`n--- Aktif Move Request'ler ---`n" -ForegroundColor Cyan

try {
    $MoveRequests = Get-MoveRequest -ErrorAction SilentlyContinue

    if ($MoveRequests) {
        foreach ($MR in $MoveRequests) {
            $Stats = Get-MoveRequestStatistics -Identity $MR.Identity
            $Color = switch ($MR.Status.ToString()) {
                "Completed"   { "Green" }
                "InProgress"  { "Cyan" }
                "Failed"      { "Red" }
                "Queued"      { "Yellow" }
                default       { "White" }
            }

            Write-Host ("{0,-25} : {1} (%{2})" -f `
                $MR.DisplayName, $MR.Status, $Stats.PercentComplete) -ForegroundColor $Color
        }
    }
    else {
        Write-Host "Aktif taşıma isteği yok." -ForegroundColor Green
    }
}
catch {
    Write-Host "[BİLGİ] Move request bilgisi alınamadı." -ForegroundColor DarkGray
}

# ============================================
# ÖZET
# ============================================
$DismountedDBs = ($DBReport | Where-Object { -not $_.Mounted }).Count
$HighWhitespace = ($DBReport | Where-Object { $_.BosAlan_Yuzde -gt 30 }).Count

Write-Host "`n--- Genel Özet ---" -ForegroundColor Cyan
Write-Host "Toplam Veritabanı : $($DBReport.Count)"
Write-Host "Mounted           : $($DBReport.Count - $DismountedDBs)" -ForegroundColor Green
Write-Host "Dismounted        : $DismountedDBs" -ForegroundColor $(if ($DismountedDBs -gt 0) { "Red" } else { "Green" })
Write-Host "Yüksek Whitespace : $HighWhitespace" -ForegroundColor $(if ($HighWhitespace -gt 0) { "Yellow" } else { "Green" })
Write-Host "Toplam Mailbox    : $TotalMailboxes`n"
