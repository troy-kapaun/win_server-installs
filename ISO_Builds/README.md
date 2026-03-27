# Windows Server Hardened ISO Build Pipeline

<!-- Build Status -->
![Build Status](https://img.shields.io/github/actions/workflow/status/troy-kapaun/win_server-installs/harden-windows.yml?branch=main&label=Build%20Status)

<!-- License -->
![License](https://img.shields.io/badge/License-MIT-blue)

<!-- Latest Release -->
![Release](https://img.shields.io/github/v/release/troy-kapaun/win_server-installs)

<!-- Downloads -->
![Downloads](https://img.shields.io/github/downloads/troy-kapaun/win_server-installs/total)

<!-- Repo Size -->
![Repo Size](https://img.shields.io/github/repo-size/troy-kapaun/win_server-installs)

<!-- Last Commit -->
![Last Commit](https://img.shields.io/github/last-commit/troy-kapaun/win_server-installs)

<!-- PowerShell Version -->
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
# Windows Server Hardened ISO Build Pipeline
Automated Azure DevOps + GitHub Actions pipeline to generate hardened Windows Server ISOs for:

✅ Windows Server 2022  
✅ Windows Server 2025  

This pipeline builds:

- Fully patched images  
- Hardened using GPO + CIS L1/L2 baselines  
- Including secedit offline hardening  
- Automatic first‑boot audit policy restore  
- Outputs hardened ISOs  

---

## 📦 Repository Structure
win_server-installs/
│
├── azure-pipelines.yml
├── .github/
│   └── workflows/
│       └── harden-windows.yml
├── README.md
│
└──ISO_Builds/
│
├── iso/                 # Downloaded ISOs (from Azure Artifacts or manual)
├── updates/             # MSU updates downloaded automatically
│   ├── 2022/
│   └── 2025/
│
├── gpo/                 # Hardening baselines
│   ├── Security.csv
│   ├── Audit.ini
│   ├── GroupPolicy/
│   └── PolicyDefinitions/
│
└── scripts/
├── Harden-WIM.ps1
├── Harden-WIM-MultiIndex.ps1
├── Build-All.ps1
├── Cleanup-WIM.ps1
├── Validate-Environment.ps1
├── Preflight-Host.ps1
├── Auto-Update-MSUs.ps1
└── config.json
---

## ✅ Requirements

- Azure DevOps Artifacts (Universal Packages)
- Project-scoped feed: `win-server-isos`
- Package names:
  - `windows-server-iso-2022`
  - `windows-server-iso-2025`

---

## ✅ GitHub Actions or Azure DevOps

Both pipelines included:

✅ Azure DevOps: `azure-pipelines.yml`  
✅ GitHub Actions: `.github/workflows/harden-windows.yml`

---

## ✅ Scripts

- `Harden-WIM.ps1` – Hardens single WIM
- `Harden-WIM-MultiIndex.ps1` – Harden all WIM indexes
- `Build-All.ps1` – Harden both 2022 + 2025
- `Auto-Update-MSUs.ps1` – Auto download latest Windows updates via MSCatalogLTS
- `Preflight-Host.ps1` – Validates local environment
- `Validate-Environment.ps1` – Checks DISM, ADK, permissions, folder structure
- `Cleanup-WIM.ps1` – Unmount stuck WIMs

---

## ✅ CIS Levels

Edit `config.json`:
{
"CIS_Level": "L1"
}
Set to `"L2"` for Level 2 enforcement.

---

## ✅ Outputs

Pipeline produces:

- `Hardened2022.iso`
- `Hardened2025.iso`

These are available as build artifacts.

---