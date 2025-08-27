# --------------------------------------------------------------------------------------
# Pester configuration for PowerShell Profile tests
# Learn more about Pester configuration at https://pester.dev/docs/usage/configuration
# --------------------------------------------------------------------------------------

@{
  # Run settings
  Run = @{
    # Paths to test files or directories
    Path = @(
      './Tests/Unit',
      './Tests/Integration'
    )
    PassThru = $true # Return test results as objects
    Exit = $false # Do not exit the session after tests
  }

  # Output settings
  Output = @{
    Verbosity = 'Detailed' # Options: 'Normal', 'Detailed', 'Diagnostic'
    StackTraceVerbosity = 'Filtered' # Options: 'None', 'Filtered', 'Full'
    CIFormat = 'Auto' # Automatically detect CI environment
  }

  # Code coverage settings
  CodeCoverage = @{
    Enabled = $false # Disabled by default, can be enabled as needed
    Path = './Functions/' # Directory to measure coverage
    OutputFormat = 'JaCoCo' # Options: 'JaCoCo', 'Cobertura', 'LCOV', 'HTML'
    OutputPath = './coverage.xml' # Output file for coverage report
  }

  # Test result reporting settings
  TestResult = @{
    Enabled = $true # Enable test result reporting
    OutputFormat = 'NUnitXml' # Options: 'NUnitXml', 'JUnitXml', 'TRX'
    OutputPath = './testresults.xml' # Output file for test results
  }
}
