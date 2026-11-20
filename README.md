# get-repos

Enterprise PowerShell utility for automated multi-repository discovery, metadata aggregation, branch/commit tracking, and batch inventory extraction across Bitbucket Server and Data Center environments.

---

## Overview

`get-repos` streamlines large-scale source code repository audits across enterprise Bitbucket instances. It queries the Bitbucket REST API across projects to retrieve detailed repository records—including default branch resolution, HTTP/SSH clone URLs, latest commit metadata, and activity timestamps—with robust throttling, pagination, and retry logic.

### Key Capabilities

- **Project Targeting**: Query specific project keys or filter across projects using wildcards or regular expressions (`-Project`, `-ProjectPattern`, `-ProjectPatternIsRegex`).
- **Flexible Authentication**: Supports both Personal Access Tokens (`-PersonalAccessToken`, Bearer auth) and credential objects (`-Credential`, Basic auth).
- **Branch Resolution with Fallback**: Inspects primary branches (`-Branch`, default `master`) with configurable fallbacks (`-FallbackBranches`, e.g., `main`).
- **Date & Name Filtering**: Filter repositories by name regex (`-RepoNameRegex`) and modification date windows (`-FromDate`, `-ToDate`).
- **Multi-Format Exports**: Export consolidated inventories to CSV (`-ExportCsv`) and JSON (`-ExportJson`), with optional per-project file splitting (`-SplitExportByProject`).
- **Parallel Execution & Resilience**: Multi-threaded querying powered by PowerShell 7+ parallel pipelines with configurable concurrency limits (`-ThrottleLimit`), inter-request throttling delays (`-ApiThrottleDelayMs`), and exponential-backoff retries (`-MaxApiRetries`).

---

## Repository Structure

```
get-repos/
├── Get-Project-Repos.ps1   # Primary extraction CLI script
├── BitbucketUtils.psm1     # Helper module (auth headers, timestamp conversion, path utils)
├── .github/
│   └── workflows/
│       ├── sbom-cbom.yml   # Automated SBOM & CBOM supply chain pipeline
│       └── security-testing.yml
├── docs/
│   └── adr/
│       └── 0001-automated-sbom-cbom-supply-chain-governance.md
└── scripts/
    ├── generate_boms.sh    # Local dual-engine SBOM and CBOM generator
    ├── scan_crypto_ast.py  # Semantic AST crypto scanner and CBOM reconciler
    ├── analyze_cbom.py     # PQC readiness analyzer & markdown report generator
    ├── test_boms.sh        # Verification test harness
    ├── attach_oci_bom.sh   # OCI artifact attachment helper
    └── fetch_oci_cbom.py   # OCI CBOM layer retrieval script
```

---

## Prerequisites

- **PowerShell**: PowerShell 7.0 or higher (`pwsh`)
- **Network**: Connectivity to target Bitbucket Server / Data Center instance
- **Authentication**: Bitbucket Personal Access Token (PAT) with read permissions or valid Bitbucket credentials

---

## Usage

### 1. Extract Repositories using a Personal Access Token (PAT)

```powershell
pwsh ./Get-Project-Repos.ps1 `
    -BitbucketBaseUrl "https://bitbucket.example.com" `
    -PersonalAccessToken "YOUR_BITBUCKET_PAT" `
    -Project "CORE", "INFRA", "DEVOPS" `
    -ExportCsv "./reports/repositories.csv" `
    -ExportJson "./reports/repositories.json"
```

### 2. Extract with Project Pattern Matching and Branch Fallback

```powershell
pwsh ./Get-Project-Repos.ps1 `
    -BitbucketBaseUrl "https://bitbucket.example.com" `
    -PersonalAccessToken "YOUR_BITBUCKET_PAT" `
    -ProjectPattern "PROD-*" `
    -Branch "main" `
    -FallbackBranches "master", "develop" `
    -SplitExportByProject `
    -ExportJson "./exports/projects.json"
```

### 3. High-Concurrency Extraction with Throttling Controls

```powershell
pwsh ./Get-Project-Repos.ps1 `
    -BitbucketBaseUrl "https://bitbucket.example.com" `
    -PersonalAccessToken "YOUR_BITBUCKET_PAT" `
    -Project "ENTERPRISE" `
    -ThrottleLimit 8 `
    -ApiThrottleDelayMs 150 `
    -MaxApiRetries 5 `
    -ExportCsv "./exports/enterprise_repos.csv"
```

---

## 🔐 SBOM, CBOM & PQC Governance

This repository integrates the [`jsoehner/jsi-bom-actions`](https://github.com/jsoehner/jsi-bom-actions) GitHub Action ([`.github/workflows/sbom-cbom.yml`](.github/workflows/sbom-cbom.yml)) for automated Software Bill of Materials (SBOM), Cryptographic Bill of Materials (CBOM), and Post-Quantum Cryptography (PQC) readiness auditing.

- **Latest Audit Report:** [`docs/security/CRYPTOGRAPHIC_AUDIT.md`](docs/security/CRYPTOGRAPHIC_AUDIT.md)
- **Learn More:** [jsoehner/jsi-bom-actions](https://github.com/jsoehner/jsi-bom-actions)

---

## License & Contributing

Contributions are welcome. Please refer to [CONTRIBUTING.md](CONTRIBUTING.md) for details on branching, testing, and Conventional Commit guidelines.
