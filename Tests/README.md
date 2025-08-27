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

All tests are derived from the `.EXAMPLE` sections in function documentation, ensuring:

- Real-world usage patterns are tested
- Documentation accuracy is validated
- Function behavior matches documented expectations

### Cross-Platform Compatibility

Tests are designed to work on:

- Windows (PowerShell Desktop 5.1 and PowerShell Core)
- macOS (PowerShell Core)
- Linux (PowerShell Core)

### Network-Aware Testing

Tests adapt to network restrictions:

- Use localhost for network testing when external access is limited
- Graceful fallback for DNS resolution tests
- Appropriate timeout handling for unreliable networks

### Meaningful Testing Focus

Tests focus on:

- ✅ Functional behavior validation
- ✅ Parameter validation and error handling
- ✅ Output structure consistency
- ✅ Performance characteristics
- ✅ Cross-platform compatibility
- ❌ Trivial existence checks (avoided as requested)

## Continuous Integration

Tests are automatically executed in GitHub Actions [CI](../.github/workflows/ci.yml) workflow:

- **PowerShell Core**: Tests run on macOS, Ubuntu, and Windows
- **PowerShell Desktop**: Tests run on Windows Server
- **Test Results**: Uploaded as NUnit XML artifacts
- **Failure Handling**: CI fails if any tests fail
