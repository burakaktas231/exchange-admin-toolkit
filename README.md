# 📧 Exchange Admin Toolkit

PowerShell toolkit for Exchange Server 2019 on-premises administration — mailbox migration, database health, shared mailboxes, transport rules, ActiveSync, and meeting room management.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?logo=powershell)
![Exchange](https://img.shields.io/badge/Exchange-2019-0078D6?logo=microsoft-exchange)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 📋 Scripts

| Script | Description |
|--------|-------------|
| `Move-MailboxDB.ps1` | Mailbox migration between databases — single, DB-to-DB, CSV, department-based. SuspendWhenReady support |
| `Get-DatabaseHealth.ps1` | Database dashboard: mount status, whitespace, mailbox balance, move requests, log stats |
| `Get-MailboxSizeReport.ps1` | All mailbox sizes sorted by usage with warning threshold |
| `Get-MailFlowStatus.ps1` | Transport queue, delivery tracking, failed messages, top senders |
| `Manage-SharedMailbox.ps1` | Shared mailbox & distribution group lifecycle. Full Access / Send As / Send on Behalf |
| `Manage-TransportRules.ps1` | Transport rules: disclaimer, size limit, KVKK keyword blocking, auto-forward |
| `Manage-MobileDevices.ps1` | ActiveSync inventory, stale device detection, remote wipe, policy audit |
| `Manage-RoomMailbox.ps1` | Meeting room & equipment mailbox: create, auto-accept, booking reports |

---

## 🚀 Usage

```powershell
git clone https://github.com/burakaktas231/exchange-admin-toolkit.git

# Mailbox migration
.\Move-MailboxDB.ps1 -SourceDB "MailboxDB01" -TargetDB "MailboxDB02"
.\Move-MailboxDB.ps1 -UserName "mehmet.yilmaz" -TargetDB "MailboxDB02"

# Database health
.\Get-DatabaseHealth.ps1 -IncludeLogStats

# Shared mailbox
.\Manage-SharedMailbox.ps1 -Action CreateShared -Name "Muhasebe" -Email "muhasebe@domain.com"
.\Manage-SharedMailbox.ps1 -Action AddAccess -Mailbox "Muhasebe" -User "ali.veli" -Permission FullAccess

# Transport rules
.\Manage-TransportRules.ps1 -Action AddDisclaimer
.\Manage-TransportRules.ps1 -Action AddBlockKeyword -Keyword "KVKK"

# Mobile devices
.\Manage-MobileDevices.ps1 -Action List
.\Manage-MobileDevices.ps1 -Action Stale -InactiveDays 90
```

## ⚙️ Requirements

- PowerShell 5.1+
- Exchange Server 2019 (compatible with 2016)
- Exchange Management Shell
- Exchange Admin or Organization Management permissions

## Author

**Burak** — IT Specialist | 7+ Years Infrastructure & Systems Administration
