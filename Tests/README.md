# pwsh-profile tests

[![ci](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml)

> This directory contains comprehensive Pester tests for this project.

## Test Structure

```plaintext
Tests/
├── Unit/                                           # Unit tests for individual functions
│   ├── Developer/                                  # Developer utility tests
│   │   └── Get-DotNetVersion.Tests.ps1             # .NET version detection tests
│   ├── NetworkAndDns/                              # Network and DNS tests
│   │   ├── Get-IPSubnet.Tests.ps1                  # IP subnet calculation tests
│   │   ├── Test-DnsNameResolution.Tests.ps1        # DNS resolution tests
│   │   ├── Test-Port.Tests.ps1                     # Network port testing tests
│   │   └── Test-TlsProtocol.Tests.ps1              # TLS protocol metadata and failure-path tests
│   ├── Security/                                   # Security function tests
│   │   ├── Protect-PathWithPassword.Tests.ps1      # File encryption tests
│   │   └── Unprotect-PathWithPassword.Tests.ps1    # File decryption tests
│   ├── Security/                                   # Security tests
│   │   └── ConvertFrom-JwtToken.Tests.ps1           # JWT token decoding tests
│   ├── SystemAdministration/                       # System administration tests
│   │   ├── Get-TlsSecurityProtocol.Tests.ps1       # TLS protocol inspection tests
│   │   ├── Get-PathPermission.Tests.ps1            # Path permissions and octal mode tests
│   │   ├── Set-TlsSecurityProtocol.Tests.ps1       # TLS protocol configuration tests
│   │   └── Start-KeepAlive.Tests.ps1               # System sleep prevention tests
│   └── Utilities/                                  # Utility function tests
│       ├── Convert-LineEnding.Tests.ps1            # Line ending conversion tests
│       ├── Get-CommandAlias.Tests.ps1              # Command alias lookup tests
│       ├── New-RandomString.Tests.ps1              # String generation utility tests
│       └── Sync-Directory.Tests.ps1                # Directory synchronization tests
├── Integration/                                    # Integration and cross-system tests
│   ├── Developer/                                  # Developer utility integration tests
│   │   ├── Remove-DotNetBuildArtifact.Tests.ps1   # .NET build cleanup integration tests
│   │   ├── Remove-GitIgnoredFile.Tests.ps1        # Git cleanup integration tests
│   │   └── Remove-NodeModule.Tests.ps1            # Node.js cleanup integration tests
│   ├── NetworkAndDns/                              # Network and DNS integration tests
│   │   ├── Test-Port.Tests.ps1                     # Real-world port testing scenarios
│   │   └── Test-TlsProtocol.Tests.ps1              # Real TLS endpoint coverage
│   ├── Security/                                   # Security integration tests
│   │   └── Protect-PathWithPassword.Tests.ps1      # End-to-end encryption workflows
│   ├── SystemAdministration/                       # System administration integration tests
│   │   └── Start-KeepAlive.Tests.ps1               # System sleep prevention integration
│   └── Utilities/                                  # Utility integration tests
│       ├── Convert-LineEnding.Tests.ps1            # Real-world line ending scenarios
│       └── Sync-Directory.Tests.ps1                # Directory synchronization integration
├── TestCleanupUtilities.ps1                        # Robust cleanup functions for tests
├── Write-TestTimingSummary.ps1                     # GitHub Actions timing summary helper
├── PesterConfiguration.psd1                        # Pester configuration file
└── README.md                                       # This file
```

## Running Tests

### Local Testing

```powershell
# Run all tests
./Invoke-Tests.ps1

# Run only unit tests
./Invoke-Tests.ps1 -TestType Unit

# Run only integration tests
./Invoke-Tests.ps1 -TestType Integration

# Run with detailed output
./Invoke-Tests.ps1 -OutputFormat Detailed

# Summarize slow test files and cases from NUnit XML output
./Tests/Write-TestTimingSummary.ps1 -Path testresults.xml -OutputPath ''
```

### CI Test Scope

The `ci` workflow runs the full unit and integration suite on PowerShell Core across macOS, Ubuntu, and Windows. Windows PowerShell Desktop 5.1 runs unit tests by default as a compatibility pass because the full integration suite duplicates Core coverage and is substantially slower on Desktop.

Use `workflow_dispatch` and set **PowerShell Desktop test scope** to `Integration` or `All` when you need an explicit Desktop integration run.

Each CI job appends a timing summary to the GitHub Actions job summary from `testresults.xml`, including the slowest test files and individual test cases.

### Docker Testing (Linux Containers)

Run tests in a Linux container from the project root using Docker Compose.

**Prerequisites:** Docker Desktop (macOS/Windows) or Docker Engine (Linux)

#### Quick Start

```bash
# Run all tests
docker compose -f Tests/docker-compose.yml run --rm pwsh-tests

# Interactive PowerShell session
docker compose -f Tests/docker-compose.yml run --rm pwsh-tests pwsh
```

#### Run Specific Test Types

```bash
# Unit tests only
docker compose -f Tests/docker-compose.yml run --rm pwsh-tests \
  pwsh -NoProfile -File ./Invoke-Tests.ps1 -TestType Unit

# Integration tests only
docker compose -f Tests/docker-compose.yml run --rm pwsh-tests \
  pwsh -NoProfile -File ./Invoke-Tests.ps1 -TestType Integration

# PSScriptAnalyzer only
docker compose -f Tests/docker-compose.yml run --rm pwsh-tests \
  pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1 -Path . -Recurse"
```

#### Container Management

```bash
# Build image (first time or after dependency changes)
docker compose -f Tests/docker-compose.yml build

# Rebuild image without cache
docker compose -f Tests/docker-compose.yml build --no-cache

# Clean up
docker compose -f Tests/docker-compose.yml down
```

**Note:** The container mounts the project root to `/workspace`, so code changes are immediately available and test results (`testresults.xml`) are saved locally.

### Manual Test Execution

Run tests manually with Pester:

```powershell
# Install Pester if not available
Install-Module Pester -Force

# Run specific test file
Invoke-Pester -Path Tests/Unit/New-RandomString.Tests.ps1

# Run with configuration
Invoke-Pester -Configuration (Import-PowerShellDataFile Tests/PesterConfiguration.psd1)
```

## Test Design Principles

### Documentation-Driven Tests

All tests are derived from the `.EXAMPLE` sections in function documentation.

### Cross-Platform Compatibility

Tests work on Windows (PowerShell Desktop 5.1 and PowerShell Core), macOS, and Linux (PowerShell Core).

### Unit vs. Integration Scope

Unit tests should avoid public network endpoints, long timeouts, and real external services. Use parameter metadata assertions, mocks, fast local fixtures, or deterministic failure paths with short explicit timeouts. Real endpoint checks belong in `Tests/Integration`.

### Robust Resource Cleanup

All tests implement comprehensive cleanup to ensure test isolation and prevent resource leaks.

#### Test Directory Cleanup Example

```powershell
AfterEach {
    try {
        if ($script:TestDir -and (Test-Path $script:TestDir)) {
            Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Multiple cleanup attempts with garbage collection
        try {
            Start-Sleep -Milliseconds 100
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            if (Test-Path $script:TestDir) {
                Get-ChildItem -Path $script:TestDir -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                Remove-Item -Path $script:TestDir -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "Failed to cleanup test directory: $script:TestDir - $_"
        }
    }
}
```

#### Background Job Cleanup Example

```powershell
AfterEach {
    try {
        # Stop and remove test jobs with timeout
        Get-Job -Name 'Test*' -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 100
        Get-Job -Name 'Test*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Failed to cleanup test jobs: $_"
    }
}
```

#### Using Centralized Cleanup Utilities

For complex cleanup scenarios, use `TestCleanupUtilities.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../TestCleanupUtilities.ps1"
}

AfterEach {
    Invoke-RobustTestCleanup -TestDirectories @($script:TestDir) -JobNamePatterns @('Test*', 'KeepAlive*')
}
```
