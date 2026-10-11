# ADR-0001: Automated SBOM & CBOM Supply Chain Governance and Post-Quantum Cryptography Readiness

- **Status**: Accepted
- **Date**: 2026-10-11
- **Security Classification**: Internal / Open Governance
- **Decision Makers**: DevSecOps & Enterprise Architecture Lead
- **Consulted / Informed**: Architecture Review Board, Security Engineering, Core Maintainers
- **Supersedes**: None

---

## 1. Context and Problem Statement

`get-repos` is an enterprise PowerShell 7 utility (`Get-Project-Repos.ps1`, `BitbucketUtils.psm1`) engineered to perform multi-repository discovery, metadata aggregation, branch/commit tracking, and batch inventory exports across Bitbucket Server and Data Center environments. Operating with elevated Personal Access Tokens (PATs) and credentials to query internal SCM APIs, the utility must maintain high supply chain and cryptographic integrity to prevent unauthorized credential exposure, dependency compromise, or insecure cryptographic algorithms.

With the enforcement of Executive Order 14028, NIST SP 800-218 (Secure Software Development Framework - SSDF), NIST SP 800-161 (Cybersecurity Supply Chain Risk Management - C-SCRM), NTIA Minimum Elements for Software Bill of Materials (SBOM), and federal Post-Quantum Cryptography (PQC) transition mandates (NIST FIPS 203/204/205, CNSA 2.0), software projects require transparent, machine-readable manifests of third-party dependencies and cryptographic primitives.

Prior to this decision, `get-repos` lacked:
1. Standardized dual-format Software Bill of Materials (SBOM) generation compliant with NTIA minimum elements (CycloneDX and SPDX).
2. Automated Cryptographic Bill of Materials (CBOM) generation tracking cryptographic algorithms, key lengths, and protocols.
3. Post-Quantum Cryptography (PQC) readiness evaluation distinguishing classical, quantum-vulnerable algorithms from quantum-safe primitives.
4. Semantic Abstract Syntax Tree (AST) scanning to correlate code call sites with inventory manifests.
5. In-pipeline verification harnesses ensuring corrupt or empty BOM artifacts fail CI prior to release or distribution.

### 1.1 Business & Compliance Drivers
- **Regulatory / Compliance**: Executive Order 14028, NIST SP 800-218 (SSDF), NIST SP 800-161 (C-SCRM), NTIA Minimum Elements for SBOMs, CNSA 2.0 PQC migration milestones.
- **Enterprise Integrity**: Ensuring that administrative and operational utilities interacting with internal code repositories maintain verifiable provenance and tamper resistance.

### 1.2 Threat & Vulnerability Context
- **Threat Vector (STRIDE)**: Tampering (malicious dependency insertion), Information Disclosure (unencrypted data in transit), Elevation of Privilege.
- **Vulnerabilities Mitigated**: CWE-1395 (Dependency on Vulnerable Third-Party Component), CWE-327 (Use of a Broken or Risky Cryptographic Algorithm), CWE-1104 (Use of Unmaintained Third-Party Components).
- **CVSS / Risk Rating**: Medium (6.2)
- **Scope**: Repository dependencies, workflow actions, build scripts, PowerShell modules, and pipeline execution environments.

---

## 2. Decision Drivers & Constraints

- Automatically generate dual-standard SBOMs: CycloneDX 1.5/1.6 JSON and SPDX 2.3 JSON using Anchore/Syft.
- Generate CycloneDX 1.6 Cryptographic Bill of Materials (CBOM) via `cbomkit-action` with fallback offline catalog reconciliation.
- Deploy dual-engine cryptographic discovery using semantic AST scanning (`scan_crypto_ast.py`) across source files.
- Provide automated CI test verification (`test_boms.sh`) verifying JSON validity, schema compliance, and asset presence.
- Evaluate Post-Quantum Cryptography (PQC) readiness and publish automated GitHub Actions Step Summaries and documentation (`analyze_cbom.py`).
- Maintain local CLI parity so developers and operators can generate and verify BOMs offline without requiring cloud CI.
- Adhere to GitHub Actions hardening standards: Node 24 runtime, immutable commit SHA pinning, and least-privilege permissions.

---

## 3. Considered Options

| Option | Approach Summary | Security Benefits | Trade-offs & Costs | Residual Risk Level |
| :--- | :--- | :--- | :--- | :--- |
| **Option A (Chosen)** | Automated dual-engine SBOM (CycloneDX + SPDX via Syft) and CBOM (cbomkit + semantic AST scanning) pipeline with PQC assessment and verification test harness. | Full NTIA compliance, cryptographic asset transparency, automated PQC readiness grading, zero vendor lock-in, local CLI parity. | Requires initial tooling setup (Syft, cbomkit, Python AST analyzer) and artifact storage in CI. | Low |
| **Option B** | Single SPDX-only SBOM generated at release time without CBOM or AST crypto scanning. | Minimal CI overhead and simple single-file generation. | Leaves zero visibility into cryptographic primitives or quantum vulnerability; lacks CycloneDX CBOM interoperability. | High |
| **Option C** | Proprietary commercial SaaS platform for supply chain governance. | Centralized enterprise dashboards managed externally. | High licensing cost, vendor lock-in, lack of offline execution for local pre-commit checks or air-gapped environments. | Medium |

---

## 4. Decision Outcome

**Chosen Option**: **Option A** — Deploy automated dual-format SBOM & CBOM generation, AST cryptographic scanning, verification testing, and PQC migration analysis.

### 4.1 Rationale
Adopting Anchore/Syft provides industry-standard dual-format SBOM generation covering CycloneDX and SPDX. Integrating `cbomkit` alongside semantic AST scanning provides an automated cryptographic inventory capable of tracking quantum-safe readiness (e.g., ML-KEM, ML-DSA) versus classical algorithms (e.g., RSA, ECC). Incorporating a deterministic verification harness (`test_boms.sh`) directly into the CI pipeline guarantees that any corrupt or missing BOM artifact breaks the build, preventing unverified releases.

### 4.2 Pipeline Architecture & Data Flow

```
[Git Commit / PR / Push]
           │
           ▼
[GitHub Actions: sbom-cbom.yml]
           │
           ├──► [1. Syft SBOM Engine] ──────────► oss/sbom.cyclonedx.json & oss/sbom.spdx.json
           │
           ├──► [2. cbomkit Action Engine] ────► oss/cbom.json
           │
           ├──► [3. Semantic AST Scanner] ─────► oss/crypto-callsites.json (Reconciliation)
           │
           ├──► [4. Verification Harness] ─────► test_boms.sh (Schema & Asset Checks)
           │
           ├──► [5. PQC Readiness Analyzer] ───► oss/crypto-analysis.json & GitHub Step Summary
           │
           ├──► [6. Audit Publishing] ─────────► docs/security/CRYPTOGRAPHIC_AUDIT.md
           │
           └──► [7. Artifact Retention] ──────► Uploaded as bom-artifacts (90 days)
```

### 4.3 Component Specifications
1. **`.github/workflows/sbom-cbom.yml`**: GitHub Actions workflow executing checkout (Node 24 `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1`), Syft, cbomkit, AST scanning, verification harness, and PQC step summary.
2. **`scripts/generate_boms.sh`**: Local execution script generating CycloneDX and SPDX SBOMs, executing cbomkit, and triggering analysis.
3. **`scripts/scan_crypto_ast.py`**: Semantic AST scanner discovering cryptographic library invocations and reconciling call sites with the CBOM.
4. **`scripts/analyze_cbom.py`**: Cryptographic analyzer assessing classical vs. post-quantum readiness, algorithm distributions, and generating markdown reports.
5. **`scripts/test_boms.sh`**: Automated verification test harness validating JSON syntax, CycloneDX schema, and cryptographic asset counts.
6. **`scripts/attach_oci_bom.sh` & `scripts/fetch_oci_cbom.py`**: OCI registry integration for attaching and retrieving BOM layers from container artifacts.

---

## 5. Security, Risk & Compliance Impact

- **Executive Order 14028 & NTIA Minimum Elements**: Both CycloneDX and SPDX formats satisfy machine-readable component identity, versioning, supplier information, and relationship graphs.
- **NIST SP 800-218 (SSDF) PW.1 / PW.8**: Supply chain controls are integrated into version control and automated pipelines with immutable commit SHAs.
- **Post-Quantum Cryptography Readiness (CNSA 2.0 / FIPS 203, 204, 205)**: Continuous automated auditing monitors for classical public-key cryptography and highlights readiness for quantum-resistant replacements.
- **Verification Gate**: The CI job fails if any BOM artifact is invalid or non-compliant, guaranteeing zero silent failures.

---

## 6. Consequences & Follow-on Actions

### 6.1 Positive Consequences
- Immediate automated visibility into all third-party software dependencies and cryptographic primitives.
- Deterministic test harness prevents deployment of unverified builds.
- Local CLI parity allows developers to audit dependencies and crypto call sites locally without CI delays.
- Full compliance with federal, defense, and enterprise supply chain assurance frameworks.

### 6.2 Negative Consequences & Trade-offs
- Build time increases by approximately 45–90 seconds per CI pipeline run.
- Ongoing maintenance required to update pinned GitHub Action SHAs and cryptographic signature patterns.

### 6.3 Follow-on Actions
- Maintain GitHub Actions commit SHA pins with automated dependency updates.
- Keep `known_cbom_catalog.json` refreshed as new cryptographic dependencies or primitives are introduced.
- Review published `docs/security/CRYPTOGRAPHIC_AUDIT.md` reports across major version releases.
