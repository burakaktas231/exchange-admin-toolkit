<#
.SYNOPSIS
    Exchange Mail Kuyruk ve Akış İzleme
.DESCRIPTION
    Exchange 2019 transport queue durumunu kontrol eder.
    Biriken mailleri, retry queue'ları ve son mail akışını raporlar.
    Mail teslim sorunlarının hızlı teşhisi için kullanılır.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.NOTES
    Exchange Management Shell gerektirir.
.EXAMPLE
    .\Get-MailFlowStatus.ps1
#>

param(
    [int]$QueueWarningThreshold = 10,   # Bu sayıdan fazla mail birikirse uyarı
    [int]$Hours = 4                      # Son kaç saatlik akışı göster
)

Write-Host "`n=== EXCHANGE MAIL AKIŞ RAPORU ===" -ForegroundColor Cyan
Write-Host "Tarih: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

# ============================================
# 1) TRANSPORT QUEUE DURUMU
# ============================================
Write-Host "--- Mail Kuyrukları ---`n" -ForegroundColor Cyan

try {
    $Queues = Get-TransportServer | Get-Queue -ErrorAction Stop

    if ($Queues) {
        foreach ($Q in $Queues) {
            $Color = if ($Q.MessageCount -ge $QueueWarningThreshold) { "Red" }
                     elseif ($Q.MessageCount -gt 0) { "Yellow" }
                     else { "Green" }

            $Flag = if ($Q.MessageCount -ge $QueueWarningThreshold) { " [BİRİKME!]" } else { "" }

            Write-Host ("{0,-15} {1,-30} : {2} mesaj ({3}){4}" -f `
                $Q.DeliveryType, $Q.NextHopDomain, $Q.MessageCount, $Q.Status, $Flag) `
                -ForegroundColor $Color
        }

        $TotalQueued = ($Queues | Measure-Object MessageCount -Sum).Sum
        Write-Host "`nToplam kuyrukta bekleyen: $TotalQueued mesaj"
    }
    else {
        Write-Host "Kuyruk bilgisi alınamadı." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[HATA] Queue bilgisi alınamadı: $_" -ForegroundColor Red
}

# ============================================
# 2) SON MESAJ TAKİP LOGLARI
# ============================================
Write-Host "`n--- Son $Hours Saatteki Mail Akışı ---`n" -ForegroundColor Cyan

try {
    $StartDate = (Get-Date).AddHours(-$Hours)

    $Tracking = Get-TransportServer | Get-MessageTrackingLog `
        -Start $StartDate `
        -ResultSize 1000 `
        -ErrorAction SilentlyContinue |
    Where-Object { $_.EventId -in @("SEND", "DELIVER", "FAIL", "DSN") }

    if ($Tracking) {
        # Olay türüne göre grupla
        $EventSummary = $Tracking | Group-Object EventId | Sort-Object Count -Descending

        foreach ($Event in $EventSummary) {
            $Color = switch ($Event.Name) {
                "DELIVER" { "Green" }
                "SEND"    { "Cyan" }
                "FAIL"    { "Red" }
                "DSN"     { "Yellow" }
                default   { "White" }
            }
            Write-Host ("{0,-12} : {1}" -f $Event.Name, $Event.Count) -ForegroundColor $Color
        }

        # Başarısız teslimatlar detay
        $FailedMessages = $Tracking | Where-Object { $_.EventId -eq "FAIL" }
        if ($FailedMessages) {
            Write-Host "`nBaşarısız Teslimatlar:" -ForegroundColor Red
            $FailedMessages | Select-Object -First 10 | ForEach-Object {
                Write-Host ("  {0} -> {1}" -f ($_.Sender), ($_.Recipients -join ", ")) -ForegroundColor Red
                Write-Host ("  Zaman: {0} | Neden: {1}" -f $_.Timestamp, $_.MessageSubject) -ForegroundColor DarkRed
                Write-Host ""
            }
        }

        # En çok mail gönderen
        Write-Host "En Çok Mail Gönderen (son $Hours saat):" -ForegroundColor Cyan
        $Tracking | Where-Object { $_.EventId -eq "SEND" } |
            Group-Object Sender | Sort-Object Count -Descending |
            Select-Object -First 5 | ForEach-Object {
                Write-Host ("  {0,-40} : {1} mesaj" -f $_.Name, $_.Count)
            }
    }
}
catch {
    Write-Host "[HATA] Mesaj takip logu okunamadı: $_" -ForegroundColor Red
}

# ============================================
# 3) VERITABANI DURUMU
# ============================================
Write-Host "`n--- Mailbox Veritabanları ---`n" -ForegroundColor Cyan

try {
    $DBs = Get-MailboxDatabase -Status -ErrorAction Stop

    foreach ($DB in $DBs) {
        $SizeGB = if ($DB.DatabaseSize) {
            [math]::Round($DB.DatabaseSize.ToBytes() / 1GB, 2)
        } else { "N/A" }

        $Mounted = if ($DB.Mounted) { "Mounted" } else { "DISMOUNTED" }
        $Color   = if ($DB.Mounted) { "Green" } else { "Red" }

        Write-Host ("{0,-30} : {1} GB | {2}" -f $DB.Name, $SizeGB, $Mounted) -ForegroundColor $Color
    }
}
catch {
    Write-Host "[HATA] Veritabanı bilgisi alınamadı: $_" -ForegroundColor Red
}
