<#
.SYNOPSIS
    Exchange Transport Kuralları Raporu ve Yönetimi
.DESCRIPTION
    Exchange mail flow rule'larını listeler, dışa aktarır
    ve yaygın senaryolar için hazır kural şablonları sunar:
    - Dış mail disclaimer ekleme
    - Ek boyut sınırlama
    - Hassas bilgi engelleme (KVKK/DLP)
    - Belirli alıcıya yönlendirme
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.NOTES
    Exchange Management Shell gerektirir.
.EXAMPLE
    .\Manage-TransportRules.ps1 -Action List
    .\Manage-TransportRules.ps1 -Action AddDisclaimer
    .\Manage-TransportRules.ps1 -Action AddSizeLimit -MaxSizeMB 25
#>

param(
    [ValidateSet("List", "Export", "AddDisclaimer", "AddSizeLimit", "AddBlockKeyword", "AddAutoForward")]
    [string]$Action = "List",

    [int]$MaxSizeMB = 25,
    [string]$Keyword,
    [string]$ForwardFrom,
    [string]$ForwardTo
)

Write-Host "`n=== EXCHANGE TRANSPORT KURAL YÖNETİMİ ===" -ForegroundColor Cyan
Write-Host "İşlem: $Action"
Write-Host "Tarih: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

switch ($Action) {

    # ============================================
    # MEVCUT KURALLARI LİSTELE
    # ============================================
    "List" {
        $Rules = Get-TransportRule | Sort-Object Priority

        if ($Rules) {
            Write-Host ("{0,-4} {1,-8} {2,-45} {3}" -f "No", "Durum", "Kural Adı", "Öncelik") -ForegroundColor White
            Write-Host ("-" * 80)

            foreach ($Rule in $Rules) {
                $Status = if ($Rule.State -eq "Enabled") { "[AÇIK]" } else { "[KAPALI]" }
                $Color  = if ($Rule.State -eq "Enabled") { "Green" } else { "DarkGray" }

                Write-Host ("{0,-4} {1,-8} {2,-45} {3}" -f `
                    $Rule.Priority, $Status, $Rule.Name, $Rule.Priority) -ForegroundColor $Color
            }
            Write-Host "`nToplam: $($Rules.Count) kural"
        }
        else {
            Write-Host "Tanımlı transport kuralı yok." -ForegroundColor Yellow
        }
    }

    # ============================================
    # KURALLARI DIŞA AKTAR
    # ============================================
    "Export" {
        $Rules = Get-TransportRule

        $ExportData = $Rules | Select-Object `
            Priority, Name, State,
            @{Name="Conditions"; Expression={ $_.Conditions -join "; " }},
            @{Name="Actions"; Expression={ $_.Actions -join "; " }},
            @{Name="Exceptions"; Expression={ $_.Exceptions -join "; " }}

        $ReportPath = "$PSScriptRoot\TransportRules_$(Get-Date -Format 'yyyy-MM-dd').csv"
        $ExportData | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
        Write-Host "[OK] Kurallar dışa aktarıldı: $ReportPath" -ForegroundColor Green
    }

    # ============================================
    # DIŞ MAİL DİSCLAİMER EKLE
    # ============================================
    "AddDisclaimer" {
        $DisclaimerHTML = @"
<div style="font-size:11px; color:#666; border-top:1px solid #ccc; padding-top:10px; margin-top:20px;">
<p><b>GİZLİLİK UYARISI / CONFIDENTIALITY NOTICE</b></p>
<p>Bu e-posta ve ekleri gizli bilgi içerebilir. Yetkili alıcı değilseniz, içeriği
kopyalamanız, dağıtmanız veya herhangi bir işlem yapmanız yasaktır. Lütfen göndereni
bilgilendirin ve bu e-postayı silin.</p>
<p>This e-mail and any attachments may contain confidential information. If you are
not the intended recipient, any copying, distribution, or use is prohibited.
Please notify the sender and delete this e-mail.</p>
</div>
"@

        try {
            New-TransportRule -Name "Dış Mail Disclaimer" `
                -SentToScope "NotInOrganization" `
                -ApplyHtmlDisclaimerLocation "Append" `
                -ApplyHtmlDisclaimerText $DisclaimerHTML `
                -ApplyHtmlDisclaimerFallbackAction "Wrap" `
                -Priority 0

            Write-Host "[OK] Dış mail disclaimer kuralı oluşturuldu." -ForegroundColor Green
            Write-Host "     Organizasyon dışına giden tüm maillere eklenecek."
        }
        catch {
            Write-Host "[HATA] Kural oluşturulamadı: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # EK BOYUT SINIRLAMASI
    # ============================================
    "AddSizeLimit" {
        $SizeKB = $MaxSizeMB * 1024

        try {
            New-TransportRule -Name "Ek Boyut Siniri ($MaxSizeMB MB)" `
                -AttachmentSizeOver $SizeKB `
                -RejectMessageReasonText "Ek boyutu $MaxSizeMB MB sınırını aşıyor. Lütfen dosyayı küçültün veya dosya paylaşım servisi kullanın." `
                -RejectMessageEnhancedStatusCode "5.2.3"

            Write-Host "[OK] $MaxSizeMB MB ek boyut sınırı kuralı oluşturuldu." -ForegroundColor Green
        }
        catch {
            Write-Host "[HATA] Kural oluşturulamadı: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # ANAHTAR KELİME ENGELLEME (basit DLP)
    # ============================================
    "AddBlockKeyword" {
        if (-not $Keyword) {
            Write-Host "Kullanım: -Action AddBlockKeyword -Keyword 'TC Kimlik'" -ForegroundColor Yellow
            Write-Host "Önceden tanımlı şablonlar:"
            Write-Host "  'KVKK'     - TC kimlik, IBAN gibi hassas veriler"
            exit
        }

        if ($Keyword -eq "KVKK") {
            # KVKK uyumlu hassas veri engelleme
            $Patterns = @(
                "\b[1-9][0-9]{10}\b",       # TC Kimlik No (11 hane)
                "\bTR\d{24}\b",              # IBAN
                "\b\d{3}-\d{3}-\d{4}\b"      # Telefon formatı
            )

            try {
                New-TransportRule -Name "KVKK - Hassas Veri Koruma" `
                    -SentToScope "NotInOrganization" `
                    -SubjectOrBodyMatchesPatterns $Patterns `
                    -RejectMessageReasonText "Bu mesaj hassas kişisel veri içeriyor olabilir. Organizasyon dışına gönderilemez. (KVKK)" `
                    -RejectMessageEnhancedStatusCode "5.7.1" `
                    -SetAuditSeverity "High"

                Write-Host "[OK] KVKK hassas veri koruma kuralı oluşturuldu." -ForegroundColor Green
                Write-Host "     TC Kimlik, IBAN ve telefon numarası dış ortama engellenecek."
            }
            catch {
                Write-Host "[HATA] Kural oluşturulamadı: $_" -ForegroundColor Red
            }
        }
        else {
            try {
                New-TransportRule -Name "Engelle - $Keyword" `
                    -SubjectOrBodyContainsWords $Keyword `
                    -SentToScope "NotInOrganization" `
                    -RejectMessageReasonText "Bu mesaj engellenen içerik ('$Keyword') içeriyor." `
                    -RejectMessageEnhancedStatusCode "5.7.1"

                Write-Host "[OK] '$Keyword' anahtar kelimesi dış maillerde engellenecek." -ForegroundColor Green
            }
            catch {
                Write-Host "[HATA] Kural oluşturulamadı: $_" -ForegroundColor Red
            }
        }
    }

    # ============================================
    # OTOMATİK YÖNLENDIRME KURALI
    # ============================================
    "AddAutoForward" {
        if (-not $ForwardFrom -or -not $ForwardTo) {
            Write-Host "Kullanım: -Action AddAutoForward -ForwardFrom 'kaynak@domain.com' -ForwardTo 'hedef@domain.com'" -ForegroundColor Yellow
            exit
        }

        try {
            New-TransportRule -Name "Yonlendirme - $ForwardFrom" `
                -From $ForwardFrom `
                -RedirectMessageTo $ForwardTo `
                -Priority 0

            Write-Host "[OK] Yönlendirme kuralı oluşturuldu:" -ForegroundColor Green
            Write-Host "     $ForwardFrom --> $ForwardTo"
        }
        catch {
            Write-Host "[HATA] Kural oluşturulamadı: $_" -ForegroundColor Red
        }
    }
}
