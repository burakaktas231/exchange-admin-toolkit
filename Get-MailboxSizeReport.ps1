<#
.SYNOPSIS
    Exchange 2019 Mailbox Boyut Raporu
.DESCRIPTION
    Tüm mailbox'ların boyutunu listeler, büyükten küçüğe sıralar.
    Belirli bir eşiği aşan kullanıcıları uyarı olarak gösterir.
    Exchange Management Shell gerektirir.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.NOTES
    Exchange Management Shell'den çalıştırılmalıdır.
#>

param(
    [int]$WarningThresholdGB = 5,     # Bu GB'ı aşanları vurgula
    [switch]$ExportCSV                 # Sonuçları CSV'ye aktar
)

$ReportPath = "$PSScriptRoot\Mailbox-Rapor_$(Get-Date -Format 'yyyy-MM-dd').csv"

Write-Host "`n=== EXCHANGE MAILBOX BOYUT RAPORU ===" -ForegroundColor Cyan
Write-Host "Uyarı Eşiği: $WarningThresholdGB GB`n"

# ============================================
# MAILBOX VERİLERİNİ ÇEK
# ============================================
try {
    $Mailboxes = Get-Mailbox -ResultSize Unlimited |
        Get-MailboxStatistics |
        Select-Object DisplayName,
            @{Name="Boyut_MB"; Expression={
                [math]::Round(
                    ($_.TotalItemSize.Value.ToString() -replace '.*\(([\d,]+)\s+bytes\).*','$1' -replace ',','') / 1MB, 2
                )
            }},
            @{Name="Boyut_GB"; Expression={
                [math]::Round(
                    ($_.TotalItemSize.Value.ToString() -replace '.*\(([\d,]+)\s+bytes\).*','$1' -replace ',','') / 1GB, 2
                )
            }},
            ItemCount,
            LastLogonTime |
        Sort-Object Boyut_MB -Descending

    # ============================================
    # SONUÇLARI GÖSTER
    # ============================================
    foreach ($MB in $Mailboxes) {
        if ($MB.Boyut_GB -ge $WarningThresholdGB) {
            Write-Host ("[UYARI] {0,-30} {1,8} GB  ({2} öğe)" -f $MB.DisplayName, $MB.Boyut_GB, $MB.ItemCount) -ForegroundColor Red
        }
        else {
            Write-Host ("        {0,-30} {1,8} GB  ({2} öğe)" -f $MB.DisplayName, $MB.Boyut_GB, $MB.ItemCount)
        }
    }

    # ============================================
    # ÖZET
    # ============================================
    $TotalGB    = [math]::Round(($Mailboxes | Measure-Object Boyut_GB -Sum).Sum, 2)
    $OverLimit  = ($Mailboxes | Where-Object { $_.Boyut_GB -ge $WarningThresholdGB }).Count

    Write-Host "`n--- Özet ---" -ForegroundColor Cyan
    Write-Host "Toplam Mailbox   : $($Mailboxes.Count)"
    Write-Host "Toplam Boyut     : $TotalGB GB"
    Write-Host "Eşik Üstü ($WarningThresholdGB GB+): $OverLimit kullanıcı"

    # ============================================
    # CSV EXPORT
    # ============================================
    if ($ExportCSV) {
        $Mailboxes | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nRapor kaydedildi: $ReportPath" -ForegroundColor Green
    }
}
catch {
    Write-Host "[HATA] Exchange komutları çalıştırılamadı." -ForegroundColor Red
    Write-Host "Exchange Management Shell'den çalıştırdığınızdan emin olun."
    Write-Host "Hata: $_"
}
