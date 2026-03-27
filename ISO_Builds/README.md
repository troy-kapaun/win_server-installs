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
ISO_Builds/
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