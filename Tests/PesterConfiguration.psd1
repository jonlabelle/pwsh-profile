# Pester configuration for PowerShell Profile tests
@{
  Run = @{
    Path = @(
      './Tests/Unit',
      './Tests/Integration'
    )
    PassThru = $true
    Exit = $false
  }
  Output = @{
    Verbosity = 'Detailed'
    StackTraceVerbosity = 'Filtered'
    CIFormat = 'Auto'
  }
  CodeCoverage = @{
    Enabled = $false  # Disabled by default, can be enabled as needed
    Path = './Functions/'
    OutputFormat = 'JaCoCo'
    OutputPath = './coverage.xml'
  }
  TestResult = @{
    Enabled = $true
    OutputFormat = 'NUnitXml'
    OutputPath = './testresults.xml'
  }
}
