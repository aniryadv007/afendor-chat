# AFENDOR CHAT: TEST RESULTS LEDGER

Date: November 7, 2026  
Execution Environment: Windows Antigravity IDE (Local Verification Suite)  
Test Harness: Node.js v24.22.1 / PowerShell 5.1 / Custom Mock S3 Test Harness  

---

## 1. Test Execution Summary

| Test Suite | Total Checks | Passed | Failed | Not Verified | Suite Exit Code |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Public GitHub Repository Access** | 4 | 0 | 4 | 0 | 0 (Check completed, 404 recorded) |
| **Public Container Registry (GHCR)** | 1 | 0 | 1 | 0 | 0 (Check completed, 403 recorded) |
| **Bash Lexer & Syntax Audit** | 13 | 13 | 0 | 0 | 0 (PASS) |
| **POSIX LF Line Ending Validation** | 20 | 20 | 0 | 0 | 0 (PASS) |
| **S3 Verification Utility (`s3-verify.sh`)** | 5 | 5 | 0 | 0 | 0 (PASS) |
| **S3 AWS SigV4 Compatibility Suite** | 8 | 8 | 0 | 0 | 0 (PASS) |
| **Storage Selection & 3-Attempt Fallback** | 5 | 5 | 0 | 0 | 0 (PASS) |
| **Live VPS & Cloud Network Tests** | 4 | 0 | 0 | 4 | N/A (Offline Development) |

---

## 2. Detailed Test Logs & Outputs

### Suite 1: Public GitHub Repository Access
- **Target URLs**:
  - `https://github.com/reign/afendor-chat`
  - `https://github.com/reign/afendor-chat.git`
  - `https://codeload.github.com/reign/afendor-chat/tar.gz/refs/heads/main`
  - `https://github.com/afendor/afendor-chat`
- **Command Executed**: `node scratch/test_github_access.cjs`
- **Actual Output**:
```json
{"url":"https://github.com/reign/afendor-chat","status":404,"location":null}
{"url":"https://github.com/reign/afendor-chat.git","status":301,"location":"https://github.com/reign/afendor-chat"}
{"url":"https://codeload.github.com/reign/afendor-chat/tar.gz/refs/heads/main","status":404,"location":null}
{"url":"https://github.com/afendor/afendor-chat","status":404,"location":null}
```
- **Status**: **FAILED** (The repository has not yet been created or made public on GitHub).

---

### Suite 2: Public Docker Registry (GHCR Anonymous Pull)
- **Target URL**: `https://ghcr.io/token?service=ghcr.io&scope=repository:afendor/afendor-api:pull`
- **Command Executed**: `node scratch/test_ghcr.cjs`
- **Actual Output**:
```text
Checking anonymous token for ghcr.io/afendor/afendor-api:pull...
Token response: {"status":403,"data":{"errors":[{"code":"DENIED","message":"requested access to the resource is denied"}]}}
```
- **Status**: **FAILED** (Public container images have not yet been published or pushed to `ghcr.io/afendor/*`).

---

### Suite 3: Shell Script Lexical and Structural Audit
- **Files Checked (13)**:
  - `deploy/bin/afendorctl`
  - `deploy/install.sh`
  - `deploy/scripts/backup.sh`
  - `deploy/scripts/dns-verify.sh`
  - `deploy/scripts/doctor.sh`
  - `deploy/scripts/healthcheck.sh`
  - `deploy/scripts/nginx-manage.sh`
  - `deploy/scripts/restore.sh`
  - `deploy/scripts/rollback.sh`
  - `deploy/scripts/s3-verify.sh`
  - `deploy/scripts/ssl-manage.sh`
  - `deploy/scripts/status.sh`
  - `deploy/scripts/update.sh`
- **Command Executed**: `node deploy/tests/test_bash_lexer.cjs`
- **Actual Output**:
```text
=== Executing Real Bash State-Machine Lexer on All Scripts ===
[PASS] deploy/bin/afendorctl -> Lexically balanced (if/fi: 16/16, case/esac: 1/1)
[PASS] deploy/install.sh -> Lexically balanced (if/fi: 51/51, case/esac: 1/1)
[PASS] deploy/scripts/backup.sh -> Lexically balanced (if/fi: 2/2, case/esac: 0/0)
[PASS] deploy/scripts/dns-verify.sh -> Lexically balanced (if/fi: 10/10, case/esac: 0/0)
[PASS] deploy/scripts/doctor.sh -> Lexically balanced (if/fi: 18/18, case/esac: 0/0)
[PASS] deploy/scripts/healthcheck.sh -> Lexically balanced (if/fi: 4/4, case/esac: 0/0)
[PASS] deploy/scripts/nginx-manage.sh -> Lexically balanced (if/fi: 11/11, case/esac: 1/1)
[PASS] deploy/scripts/restore.sh -> Lexically balanced (if/fi: 2/2, case/esac: 0/0)
[PASS] deploy/scripts/rollback.sh -> Lexically balanced (if/fi: 10/10, case/esac: 0/0)
[PASS] deploy/scripts/s3-verify.sh -> Lexically balanced (if/fi: 4/4, case/esac: 1/1)
[PASS] deploy/scripts/ssl-manage.sh -> Lexically balanced (if/fi: 18/18, case/esac: 1/1)
[PASS] deploy/scripts/status.sh -> Lexically balanced (if/fi: 0/0, case/esac: 0/0)
[PASS] deploy/scripts/update.sh -> Lexically balanced (if/fi: 3/3, case/esac: 0/0)

Lexer Audit: 13 passed, 0 failed out of 13 scripts.
```
- **Status**: **VERIFIED** (Exit Code: 0)

---

### Suite 4: S3 Verification Utility (`deploy/scripts/s3-verify.sh`)
- **Target**: Embedded Node.js runner inside `s3-verify.sh` against `MockS3Server`
- **Command Executed**: `node deploy/tests/test_s3_verify.cjs`
- **Actual Output**:
```text
=== Testing S3 Verification Logic Against Mock S3 ===
[PASS] Test 1: S3 Put/Get/Delete happy path succeeded
[PASS] Test 2: Invalid credentials correctly rejected
[PASS] Test 3: Non-existent bucket correctly rejected
[PASS] Test 4: DeleteObject failure correctly detected
[PASS] Test 5: Corrupted GetObject content detected

Results: 5 passed, 0 failed.
```
- **Status**: **VERIFIED** (Exit Code: 0)

---

### Suite 5: S3 Comprehensive Compatibility Suite
- **Target**: AWS SigV4, Path-style vs Virtual-host, error handling, DNS/port failures
- **Command Executed**: `node deploy/tests/test_s3_suite.cjs`
- **Actual Output**:
```text
=== AFENDOR CHAT: S3 Comprehensive Compatibility Test Suite ===
[PASS] Connection Refused / Port Closed
[PASS] Malformed Endpoint URL
[PASS] DNS Failure / Unresolvable Host
[PASS] Missing Mandatory Credentials Gating
[PASS] Path-Style Addressing
[PASS] Virtual-Host-Style Fallback for IP/Port
[PASS] PutObject Permission Denied (HTTP 403)
[PASS] DeleteObject Permission Denied (HTTP 403)

S3 Suite Summary: 8 passed, 0 failed out of 8 tests.
```
- **Status**: **VERIFIED** (Exit Code: 0)

---

### Suite 6: Storage Selection & 3-Attempt Fallback Scenarios
- **Target**: Scenarios A, B, C, D (Credential retention, automated fallback, zero secret leakage)
- **Command Executed**: `node deploy/tests/test_storage_fallback.cjs`
- **Actual Output**:
```text
=== Testing S3 Selection & Fallback Scenarios ===

[Testing Scenario A] Successful S3 configuration...
  [PASS] Scenario A: Valid S3 saved, SeaweedFS not unnecessarily activated

[Testing Scenario B] 3 failed S3 attempts -> Automated fallback to SeaweedFS...
  [PASS] Scenario B: 3 failures triggered automatic fallback to SeaweedFS without aborting
  [PASS] Scenario B: Failed credentials wiped from memory, zero leaked secrets in .env or state

[Testing Scenario C] Interrupted installation resume safety...
  [PASS] Scenario C: Existing secrets and configuration preserved on resume

[Testing Scenario D] S3 outage post-installation...
  [PASS] Scenario D: Persistent named volumes preserved; no destructive automated migration

Scenario Suite Results: 5 passed, 0 failed.
```
- **Status**: **VERIFIED** (Exit Code: 0)

---

### Suite 7: Tests Not Executed (Offline Constraints)
The following tests could not be executed on the local development machine:
1. **Live Let's Encrypt ACME HTTP-01 Validation**: Requires a public routable IPv4 and port 80. (**NOT VERIFIED**)
2. **LiveKit WebRTC UDP Media Flow over WAN**: Requires remote STUN/TURN UDP packet exchange over public internet. (**NOT VERIFIED**)
3. **Live GCP VPS Docker Compose Up**: Per rule, production VPS was not accessed. (**NOT VERIFIED**)
4. **Live Backblaze B2 WAN API Calls**: Live B2 credentials were not provisioned. (**NOT VERIFIED**)

