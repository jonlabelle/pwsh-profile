# pwsh-profile tests

[![ci](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml)

> This directory contains comprehensive Pester tests for this project.

## Test Structure

```plaintext
Tests/
├── Unit/                                 # Unit tests for individual functions
│   ├── New-RandomString.Tests.ps1        # String generation utility tests
│   ├── Get-CommandAlias.Tests.ps1        # Command alias lookup tests
│   ├── Get-IPSubnet.Tests.ps1            # IP subnet calculation tests
│   ├── Test-DnsNameResolution.Tests.ps1  # DNS resolution tests
│   ├── Test-Port.Tests.ps1               # Network port testing tests
│   └── Get-DotNetVersion.Tests.ps1       # .NET version detection tests
├── Integration/                          # Integration and cross-system tests
│   └── Test-Port.Tests.ps1               # Real-world port testing scenarios
├── TestCleanupUtilities.ps1              # Robust cleanup functions for tests
├── PesterConfiguration.psd1              # Pester configuration file
└── README.md                             # This file
```

## Running Tests

```powershell
# Run all tests
./Invoke-Tests.ps1

# Run only unit tests
./Invoke-Tests.ps1 -TestType Unit

# Run only integration tests
./Invoke-Tests.ps1 -TestType Integration

# Run with detailed output
./Invoke-Tests.ps1 -OutputFormat Detailed
```

### Manual Test Execution

```powershell
# Install Pester if not available
Install-Module Pester -Force

# Run specific test file
Invoke-Pester -Path Tests/Unit/New-RandomString.Tests.ps1

# Run with configuration
Invoke-Pester -Configuration (Import-PowerShellDataFile Tests/PesterConfiguration.psd1)
```

## Test Design Principles

### Based on Documentation Examples

All tests are derived from the `.EXAMPLE` sections in function documentation

### Cross-Platform Compatibility

Tests are designed to work on:

- Windows (PowerShell Desktop 5.1 and PowerShell Core)
- macOS (PowerShell Core)
- Linux (PowerShell Core)

### Robust Resource Cleanup

All tests implement comprehensive cleanup to ensure test isolation and prevent resource leaks:

#### Test Directory Cleanup

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

#### Background Job Cleanup

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

#### Using TestCleanupUtilities.ps1

For complex cleanup scenarios, tests can use the centralized cleanup utilities:

```powershell
BeforeAll {
    . "$PSScriptRoot/../TestCleanupUtilities.ps1"
}

AfterEach {
    Invoke-RobustTestCleanup -TestDirectories @($script:TestDir) -JobNamePatterns @('Test*', 'KeepAlive*')
}
```
