# PowerShell Profile Test Suite

[![ci](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml/badge.svg)](https://github.com/jonlabelle/pwsh-profile/actions/workflows/ci.yml)

> This directory contains comprehensive Pester 5.x tests for the PowerShell Profile project.

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

### Quick Start

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

## Test Coverage

### Unit Tests (122 tests total)

#### New-RandomString (17 tests)

- ✅ Basic functionality (default parameters, length specification)
- ✅ Character set validation (numbers, letters, symbols)
- ✅ ExcludeAmbiguous parameter behavior
- ✅ IncludeSymbols parameter functionality
- ✅ Secure parameter cryptographic generation
- ✅ Parameter validation and error handling

#### Get-CommandAlias (11 tests)

- ✅ Basic alias lookup for known commands
- ✅ Wildcard pattern support
- ✅ Pipeline input processing
- ✅ Formatted table output validation
- ✅ Parameter validation and error handling
- ✅ Cross-platform compatibility

#### Get-IPSubnet (17 tests)

- ✅ CIDR notation input parsing
- ✅ IP address and subnet mask calculations
- ✅ Complex subnet calculations and methods
- ✅ Binary representation generation
- ✅ Decimal conversion accuracy
- ✅ Parameter validation for IP addresses and prefix lengths

#### Test-DnsNameResolution (24 tests)

- ✅ DNS resolution functionality (adapted for localhost)
- ✅ IPv4 and IPv6 record type support
- ✅ Custom DNS server parameter handling
- ✅ Invalid domain error handling
- ✅ Pipeline input support
- ✅ Verbose output and logging validation

#### Test-Port (28 tests)

- ✅ TCP and UDP port testing
- ✅ Pipeline input for ports and computers
- ✅ Timeout and error handling
- ✅ Output structure validation
- ✅ Multiple computer support
- ✅ Performance characteristics

#### Get-DotNetVersion (26 tests)

- ✅ .NET Framework and .NET Core detection
- ✅ Parameter set validation
- ✅ Cross-platform runtime detection
- ✅ SDK information inclusion
- ✅ Remote computer support
- ✅ Output structure consistency

### Integration Tests (24 tests)

#### Test-Port Integration

- ✅ Real-world port testing scenarios
- ✅ Performance testing and reliability
- ✅ Network edge case handling
- ✅ Protocol-specific behavior validation
- ✅ Service discovery patterns
- ✅ Stress and reliability testing

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

Tests are automatically executed in GitHub Actions CI pipeline:

- **PowerShell Core**: Tests run on macOS, Ubuntu, and Windows
- **PowerShell Desktop**: Tests run on Windows Server
- **Test Results**: Uploaded as NUnit XML artifacts
- **Failure Handling**: CI fails if any tests fail

### CI Configuration

```yaml
- name: Run Pester tests
  shell: pwsh
  run: |
    ./Invoke-Tests.ps1 -TestType All -OutputFormat Normal

    if ($LASTEXITCODE -ne 0) {
      Write-Error "Tests failed with exit code $LASTEXITCODE" -ErrorAction Stop
    }
```

## Troubleshooting

### Common Issues

1. **Network Connectivity**: Some tests require localhost network access
2. **Parameter Sets**: Complex functions like Get-DotNetVersion have intricate parameter validation
3. **Platform Differences**: Some functions behave differently on different platforms

### Test Environment Requirements

- Pester 5.x (installed automatically in CI)
- PowerShell 5.1+ or PowerShell Core 6.2+
- Network access to localhost for integration tests
- Sufficient permissions for port testing

## Contributing

When adding new tests:

1. Follow the existing test structure and naming conventions
2. Base tests on function documentation examples
3. Include both positive and negative test cases
4. Ensure cross-platform compatibility
5. Add meaningful assertions, not trivial checks
6. Update this README if adding new test categories

## Test Maintenance

- Tests are maintained alongside function changes
- CI pipeline ensures tests remain valid
- Test failures indicate either function bugs or test updates needed
- Documentation examples drive test case creation
