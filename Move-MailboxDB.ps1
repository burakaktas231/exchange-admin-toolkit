<#
.SYNOPSIS
    Exchange Mailbox Veritabanları Arası Taşıma
.DESCRIPTION
    Mailbox'ları bir veritabanından diğerine taşır.
    Tekli, toplu (CSV) ve departmana göre toplu taşıma destekler.
    Veritabanı dengeleme ve bakım öncesi tahliye için kullanılır.
.AUTHOR
    Burak - ASC Hukuk IT
.VERSION
    1.0
.NOTES
    Exchange Management Shell gerektirir.
.EXAMPLE
    .\Move-MailboxDB.ps1 -UserName "mehmet.yilmaz" -TargetDB "MailboxDB02"
    .\Move-MailboxDB.ps1 -SourceDB "MailboxDB01" -TargetDB "MailboxDB02"
    .\Move-MailboxDB.ps1 -CSVPath ".\tasima-listesi.csv" -TargetDB "MailboxDB02"
    .\Move-MailboxDB.ps1 -Department "Dava" -TargetDB "MailboxDB02"
#>

param(
    [string]$UserName,         # Tek kullanıcı taşıma
    [string]$SourceDB,         # Kaynak DB'den toplu taşıma
    [string]$TargetDB,         # Hedef veritabanı (zorunlu)
    [string]$CSVPath,          # CSV'den liste ile taşıma
    [string]$Department,       # Departmana göre toplu taşıma
    [int]$BadItemLimit = 5,    # Tolere edilecek bozuk öğe sayısı
    [switch]$SuspendWhenReady  # Tamamlanınca beklet (mesai dışı geçiş için)
)

if (-not $TargetDB) {
    Write-Host "[HATA] -TargetDB parametresi zorunludur." -ForegroundColor Red
    Write-Host "Mevcut veritabanları:"
    Get-MailboxDatabase | Format-Table Name, ServerName, DatabaseSize -AutoSize
    exit 1
}

Write-Host "`n=== MAILBOX TAŞIMA İŞLEMİ ===" -ForegroundColor Cyan
Write-Host "Hedef DB   : $TargetDB"
Write-Host "Bad Item   : $BadItemLimit"
Write-Host "Tarih      : $(Get-Date -Format 'dd.MM.yyyy HH:mm')`n"

# ============================================
# HEDEF DB KONTROLÜ
# ============================================
try {
    $TargetDatabase = Get-MailboxDatabase -Identity $TargetDB -Status -ErrorAction Stop
    $FreeGB = [math]::Round(($TargetDatabase.AvailableNewMailboxSpace.ToBytes()) / 1GB, 2)
    Write-Host "Hedef DB Boş Alan: $FreeGB GB`n" -ForegroundColor $(if ($FreeGB -lt 10) { "Yellow" } else { "Green" })
}
catch {
    Write-Host "[HATA] Hedef veritabanı bulunamadı: $TargetDB" -ForegroundColor Red
    exit 1
}

# ============================================
# TAŞINACAK MAILBOX'LARI BELİRLE
# ============================================
$Mailboxes = @()

# Mod 1: Tek kullanıcı
if ($UserName) {
    try {
        $Mailboxes += Get-Mailbox -Identity $UserName -ErrorAction Stop
        Write-Host "Mod: Tek kullanıcı taşıma ($UserName)" -ForegroundColor White
    }
    catch {
        Write-Host "[HATA] Mailbox bulunamadı: $UserName" -ForegroundColor Red
        exit 1
    }
}
# Mod 2: Kaynak DB'den toplu
elseif ($SourceDB) {
    $Mailboxes = Get-Mailbox -Database $SourceDB -ResultSize Unlimited
    Write-Host "Mod: Veritabanı taşıma ($SourceDB --> $TargetDB)" -ForegroundColor White
    Write-Host "Toplam mailbox: $($Mailboxes.Count)"
}
# Mod 3: CSV'den
elseif ($CSVPath) {
    if (-not (Test-Path $CSVPath)) {
        Write-Host "[HATA] CSV dosyası bulunamadı: $CSVPath" -ForegroundColor Red
        exit 1
    }
    $CSVData = Import-Csv $CSVPath
    foreach ($Row in $CSVData) {
        try {
            $Mailboxes += Get-Mailbox -Identity $Row.SamAccountName -ErrorAction Stop
        }
        catch {
            Write-Host "[UYARI] Mailbox bulunamadı: $($Row.SamAccountName)" -ForegroundColor Yellow
        }
    }
    Write-Host "Mod: CSV'den taşıma ($($Mailboxes.Count) mailbox)" -ForegroundColor White
}
# Mod 4: Departmana göre
elseif ($Department) {
    $DeptUsers = Get-ADUser -Filter { Department -eq $Department -and Enabled -eq $true } |
        Select-Object -ExpandProperty SamAccountName
    foreach ($Sam in $DeptUsers) {
        try {
            $Mailboxes += Get-Mailbox -Identity $Sam -ErrorAction SilentlyContinue
        }
        catch { }
    }
    Write-Host "Mod: Departman taşıma ($Department - $($Mailboxes.Count) mailbox)" -ForegroundColor White
}
else {
    Write-Host "Kullanım:" -ForegroundColor Yellow
    Write-Host "  Tekli  : .\Move-MailboxDB.ps1 -UserName 'ali.veli' -TargetDB 'MailboxDB02'"
    Write-Host "  Toplu  : .\Move-MailboxDB.ps1 -SourceDB 'MailboxDB01' -TargetDB 'MailboxDB02'"
    Write-Host "  CSV    : .\Move-MailboxDB.ps1 -CSVPath '.\liste.csv' -TargetDB 'MailboxDB02'"
    Write-Host "  Dept.  : .\Move-MailboxDB.ps1 -Department 'Dava' -TargetDB 'MailboxDB02'"
    exit
}

# Zaten hedef DB'de olanları çıkar
$Mailboxes = $Mailboxes | Where-Object { $_.Database -ne $TargetDB }

if ($Mailboxes.Count -eq 0) {
    Write-Host "`nTaşınacak mailbox yok (hepsi zaten hedef DB'de)." -ForegroundColor Green
    exit
}

# ============================================
# TAŞIMA BAŞLAT
# ============================================
Write-Host "`n--- Taşınacak Mailbox'lar ---" -ForegroundColor Cyan
$Mailboxes | ForEach-Object {
    Write-Host "  $($_.DisplayName) ($($_.Database) --> $TargetDB)"
}

$Confirm = Read-Host "`n$($Mailboxes.Count) mailbox taşınacak. Onaylıyor musunuz? (E/H)"
if ($Confirm -ne "E") {
    Write-Host "İşlem iptal edildi." -ForegroundColor Yellow
    exit
}

$SuccessCount = 0
$ErrorCount   = 0

foreach ($MB in $Mailboxes) {
    try {
        $MoveParams = @{
            Identity                   = $MB.Identity
            TargetDatabase             = $TargetDB
            BadItemLimit               = $BadItemLimit
            AcceptLargeDataLoss        = $false
            Confirm                    = $false
        }

        if ($SuspendWhenReady) {
            $MoveParams.SuspendWhenReadyToComplete = $true
        }

        New-MoveRequest @MoveParams -ErrorAction Stop

        Write-Host "[OK] $($MB.DisplayName) - Taşıma isteği oluşturuldu" -ForegroundColor Green
        $SuccessCount++
    }
    catch {
        Write-Host "[HATA] $($MB.DisplayName) - $_" -ForegroundColor Red
        $ErrorCount++
    }
}

# ============================================
# ÖZET
# ============================================
Write-Host "`n--- Özet ---" -ForegroundColor Cyan
Write-Host "Başarılı İstek : $SuccessCount"
Write-Host "Hatalı         : $ErrorCount"
if ($SuspendWhenReady) {
    Write-Host "`n[BİLGİ] SuspendWhenReady aktif. Tamamlamak için:" -ForegroundColor Yellow
    Write-Host "  Get-MoveRequest | Resume-MoveRequest"
}
Write-Host "`nTaşıma durumunu izlemek için:" -ForegroundColor Cyan
Write-Host "  Get-MoveRequest | Get-MoveRequestStatistics"
Write-Host "  Get-MoveRequest -MoveStatus Completed | Remove-MoveRequest`n"
