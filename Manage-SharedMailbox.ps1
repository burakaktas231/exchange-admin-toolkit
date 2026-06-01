<#
.SYNOPSIS
    Dağıtım Grubu ve Paylaşımlı Mailbox Yönetimi
.DESCRIPTION
    Exchange dağıtım gruplarını ve paylaşımlı mailbox'ları yönetir:
    - Dağıtım grubu oluşturma/listeleme
    - Paylaşımlı mailbox oluşturma ve yetkilendirme
    - Üye ekleme/çıkarma
    - Tam erişim ve Send-As yetkileri
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.NOTES
    Exchange Management Shell gerektirir.
.EXAMPLE
    .\Manage-SharedMailbox.ps1 -Action CreateShared -Name "Muhasebe" -Email "muhasebe@aschukuk.com"
    .\Manage-SharedMailbox.ps1 -Action AddAccess -Mailbox "muhasebe" -User "ali.veli" -Permission FullAccess
    .\Manage-SharedMailbox.ps1 -Action CreateDL -Name "Tüm Avukatlar" -Email "avukatlar@aschukuk.com"
    .\Manage-SharedMailbox.ps1 -Action ListAll
#>

param(
    [ValidateSet("CreateShared", "AddAccess", "RemoveAccess", "CreateDL", "AddDLMember", "ListAll", "Report")]
    [string]$Action = "ListAll",

    [string]$Name,
    [string]$Email,
    [string]$Mailbox,
    [string]$User,

    [ValidateSet("FullAccess", "SendAs", "SendOnBehalf")]
    [string]$Permission = "FullAccess",

    [string]$Department
)

Write-Host "`n=== PAYLAŞIMLI MAILBOX & DAĞITIM GRUBU YÖNETİMİ ===" -ForegroundColor Cyan
Write-Host "İşlem: $Action"
Write-Host "Tarih: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

switch ($Action) {

    # ============================================
    # PAYLAŞIMLI MAILBOX OLUŞTUR
    # ============================================
    "CreateShared" {
        if (-not $Name -or -not $Email) {
            Write-Host "Kullanım: -Action CreateShared -Name 'İsim' -Email 'adres@domain.com'" -ForegroundColor Yellow
            exit
        }

        try {
            New-Mailbox -Name $Name `
                        -DisplayName $Name `
                        -PrimarySmtpAddress $Email `
                        -Shared

            Write-Host "[OK] Paylaşımlı mailbox oluşturuldu:" -ForegroundColor Green
            Write-Host "     İsim  : $Name"
            Write-Host "     Email : $Email"
            Write-Host "`nYetki vermek için:"
            Write-Host "  .\Manage-SharedMailbox.ps1 -Action AddAccess -Mailbox '$Name' -User 'kullanıcı' -Permission FullAccess"
        }
        catch {
            Write-Host "[HATA] Mailbox oluşturulamadı: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # ERİŞİM YETKİSİ EKLE
    # ============================================
    "AddAccess" {
        if (-not $Mailbox -or -not $User) {
            Write-Host "Kullanım: -Action AddAccess -Mailbox 'isim' -User 'kullanıcı' -Permission FullAccess" -ForegroundColor Yellow
            exit
        }

        try {
            switch ($Permission) {
                "FullAccess" {
                    Add-MailboxPermission -Identity $Mailbox -User $User `
                        -AccessRights FullAccess -InheritanceType All -AutoMapping $true
                    Write-Host "[OK] $User --> $Mailbox : Full Access verildi (AutoMapping açık)" -ForegroundColor Green
                }
                "SendAs" {
                    Add-ADPermission -Identity $Mailbox -User $User `
                        -ExtendedRights "Send As"
                    Write-Host "[OK] $User --> $Mailbox : Send As verildi" -ForegroundColor Green
                }
                "SendOnBehalf" {
                    Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Add=$User}
                    Write-Host "[OK] $User --> $Mailbox : Send on Behalf verildi" -ForegroundColor Green
                }
            }
        }
        catch {
            Write-Host "[HATA] Yetki verilemedi: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # ERİŞİM YETKİSİ KALDIR
    # ============================================
    "RemoveAccess" {
        if (-not $Mailbox -or -not $User) {
            Write-Host "Kullanım: -Action RemoveAccess -Mailbox 'isim' -User 'kullanıcı' -Permission FullAccess" -ForegroundColor Yellow
            exit
        }

        try {
            switch ($Permission) {
                "FullAccess" {
                    Remove-MailboxPermission -Identity $Mailbox -User $User `
                        -AccessRights FullAccess -InheritanceType All -Confirm:$false
                    Write-Host "[OK] $User --> $Mailbox : Full Access kaldırıldı" -ForegroundColor Green
                }
                "SendAs" {
                    Remove-ADPermission -Identity $Mailbox -User $User `
                        -ExtendedRights "Send As" -Confirm:$false
                    Write-Host "[OK] $User --> $Mailbox : Send As kaldırıldı" -ForegroundColor Green
                }
                "SendOnBehalf" {
                    Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Remove=$User}
                    Write-Host "[OK] $User --> $Mailbox : Send on Behalf kaldırıldı" -ForegroundColor Green
                }
            }
        }
        catch {
            Write-Host "[HATA] Yetki kaldırılamadı: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # DAĞITIM GRUBU OLUŞTUR
    # ============================================
    "CreateDL" {
        if (-not $Name -or -not $Email) {
            Write-Host "Kullanım: -Action CreateDL -Name 'Grup Adı' -Email 'grup@domain.com'" -ForegroundColor Yellow
            exit
        }

        try {
            New-DistributionGroup -Name $Name `
                                 -DisplayName $Name `
                                 -PrimarySmtpAddress $Email `
                                 -MemberJoinRestriction "ApprovalRequired" `
                                 -MemberDepartRestriction "Open"

            Write-Host "[OK] Dağıtım grubu oluşturuldu:" -ForegroundColor Green
            Write-Host "     İsim  : $Name"
            Write-Host "     Email : $Email"

            # Departmana göre otomatik üye ekle
            if ($Department) {
                $DeptUsers = Get-ADUser -Filter { Department -eq $Department -and Enabled -eq $true } |
                    Select-Object -ExpandProperty SamAccountName

                $AddedCount = 0
                foreach ($Sam in $DeptUsers) {
                    try {
                        Add-DistributionGroupMember -Identity $Name -Member $Sam -ErrorAction Stop
                        $AddedCount++
                    }
                    catch { }
                }
                Write-Host "     $AddedCount kullanıcı ($Department departmanı) otomatik eklendi." -ForegroundColor Green
            }
        }
        catch {
            Write-Host "[HATA] Dağıtım grubu oluşturulamadı: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # DAĞITIM GRUBUNA ÜYE EKLE
    # ============================================
    "AddDLMember" {
        if (-not $Mailbox -or -not $User) {
            Write-Host "Kullanım: -Action AddDLMember -Mailbox 'GrupAdı' -User 'kullanıcı'" -ForegroundColor Yellow
            exit
        }

        try {
            Add-DistributionGroupMember -Identity $Mailbox -Member $User
            Write-Host "[OK] $User --> $Mailbox grubuna eklendi." -ForegroundColor Green
        }
        catch {
            Write-Host "[HATA] Üye eklenemedi: $_" -ForegroundColor Red
        }
    }

    # ============================================
    # TÜM PAYLAŞIMLI MAILBOX'LARI LİSTELE
    # ============================================
    "ListAll" {
        Write-Host "--- Paylaşımlı Mailbox'lar ---`n" -ForegroundColor Cyan

        $SharedMBs = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited

        if ($SharedMBs) {
            foreach ($SMB in $SharedMBs) {
                Write-Host "$($SMB.DisplayName)" -ForegroundColor White
                Write-Host "  Email: $($SMB.PrimarySmtpAddress)"

                # Yetkililer
                $Perms = Get-MailboxPermission -Identity $SMB.Identity |
                    Where-Object { $_.User -notmatch "NT AUTHORITY|S-1-5" -and $_.IsInherited -eq $false }

                if ($Perms) {
                    foreach ($P in $Perms) {
                        Write-Host "  --> $($P.User) : $($P.AccessRights)" -ForegroundColor DarkCyan
                    }
                }
                Write-Host ""
            }
            Write-Host "Toplam: $($SharedMBs.Count) paylaşımlı mailbox"
        }
        else {
            Write-Host "Paylaşımlı mailbox bulunamadı."
        }

        Write-Host "`n--- Dağıtım Grupları ---`n" -ForegroundColor Cyan

        $DLs = Get-DistributionGroup -ResultSize Unlimited

        if ($DLs) {
            foreach ($DL in $DLs) {
                $MemberCount = (Get-DistributionGroupMember -Identity $DL.Identity -ResultSize Unlimited).Count
                Write-Host ("{0,-35} ({1}) - {2} üye" -f $DL.DisplayName, $DL.PrimarySmtpAddress, $MemberCount)
            }
            Write-Host "`nToplam: $($DLs.Count) dağıtım grubu"
        }
    }

    # ============================================
    # DETAYLI RAPOR
    # ============================================
    "Report" {
        Write-Host "--- Paylaşımlı Mailbox Yetki Matrisi ---`n" -ForegroundColor Cyan

        $SharedMBs = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited

        foreach ($SMB in $SharedMBs) {
            Write-Host "$($SMB.DisplayName) ($($SMB.PrimarySmtpAddress))" -ForegroundColor White

            # Full Access
            $FullAccess = Get-MailboxPermission -Identity $SMB.Identity |
                Where-Object { $_.User -notmatch "NT AUTHORITY|S-1-5" -and $_.IsInherited -eq $false }

            # Send As
            $SendAs = Get-ADPermission -Identity $SMB.DistinguishedName |
                Where-Object { $_.ExtendedRights -like "*Send-As*" -and $_.User -notmatch "S-1-5" }

            # Send on Behalf
            $SendOnBehalf = $SMB.GrantSendOnBehalfTo

            if ($FullAccess) {
                $FullAccess | ForEach-Object {
                    Write-Host "  [FullAccess]    $($_.User)" -ForegroundColor Green
                }
            }
            if ($SendAs) {
                $SendAs | ForEach-Object {
                    Write-Host "  [SendAs]        $($_.User)" -ForegroundColor Cyan
                }
            }
            if ($SendOnBehalf) {
                $SendOnBehalf | ForEach-Object {
                    Write-Host "  [SendOnBehalf]  $_" -ForegroundColor DarkCyan
                }
            }
            Write-Host ""
        }
    }
}
