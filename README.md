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

## Automated SBOM & CBOM Supply Chain Pipeline

`get-repos` integrates an automated Software Bill of Materials (SBOM) and Cryptographic Bill of Materials (CBOM) governance pipeline to satisfy Executive Order 14028, NIST SP 800-218 (SSDF), NIST SP 800-161 (C-SCRM), NTIA Minimum Elements, and federal Post-Quantum Cryptography (PQC) transition mandates (NIST FIPS 203/204/205, CNSA 2.0).

For detailed architectural decisions, trade-offs, and compliance mappings, refer to [ADR-0001: Automated SBOM & CBOM Supply Chain Governance](docs/adr/0001-automated-sbom-cbom-supply-chain-governance.md).

### CI/CD Workflow Stages (`.github/workflows/sbom-cbom.yml`)

The GitHub Actions workflow triggers on push to `main`/`master`, semantic tags (`v*`), pull requests, and manual triggers (`workflow_dispatch`). It executes across 7 discrete stages:

1. **Dual-Format SBOM Generation**: Employs Anchore/Syft to produce dual-standard machine-readable inventories in CycloneDX 1.6 JSON (`oss/sbom.cyclonedx.json`) and SPDX 2.3 JSON (`oss/sbom.spdx.json`).
2. **CBOM Generation**: Executes `cbomkit-action` to discover cryptographic components, algorithms, and key sizes (`oss/cbom.json`).
3. **Semantic AST Cryptographic Scan & Reconciliation**: Runs `scripts/scan_crypto_ast.py` across source code to detect cryptographic API call sites and reconcile findings directly against the CBOM.
4. **Automated Verification Test Harness**: Executes `scripts/test_boms.sh` to validate schema conformance, non-empty manifests, and minimum component thresholds. Any malformed artifact fails the build.
5. **Post-Quantum Cryptography (PQC) Readiness Assessment**: Analyzes cryptographic algorithms using `scripts/analyze_cbom.py`, evaluating quantum vulnerability vs. post-quantum readiness (CNSA 2.0, FIPS 203/204/205) and rendering a GitHub Actions Step Summary.
6. **Audit Report Publication**: On push to `main`, updates and publishes `docs/security/CRYPTOGRAPHIC_AUDIT.md`.
7. **Artifact Archival**: Uploads all generated BOM artifacts as workflow run artifacts with 90-day retention.

### Local Script Tooling

Developers and DevSecOps engineers can execute the identical BOM toolchain locally:

```bash
# Generate dual-format SBOMs and CBOM locally into oss/
bash scripts/generate_boms.sh -t dir .

# Run semantic AST crypto scanning and CBOM reconciliation
python3 scripts/scan_crypto_ast.py . --cbom oss/cbom.json --output-json oss/crypto-callsites.json

# Execute verification test harness
bash scripts/test_boms.sh oss

# Generate PQC readiness assessment report
python3 scripts/analyze_cbom.py oss/cbom.json \
    --sbom oss/sbom.spdx.json \
    --markdown oss/crypto-summary.md
```

---

## License & Contributing

Contributions are welcome. Please refer to [CONTRIBUTING.md](CONTRIBUTING.md) for details on branching, testing, and Conventional Commit guidelines.
