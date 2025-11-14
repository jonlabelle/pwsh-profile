# PSScriptAnalyzerSettings.psd1
#
# This file is used to configure the behavior of PSScriptAnalyzer,
# a static code checker for PowerShell scripts.
#
# Example usage:
# Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1 -Path . -Recurse

@{
  # Exclude specific rules globally
  ExcludeRules = @(
    'PSAvoidUsingWriteHost', # Used intentionally in certain scenarios
    'PSUseShouldProcessForStateChangingFunctions', # Can soon remove this
    'PSAvoidGlobalVars', # Required for updating $Profile
    'PSReviewUnusedParameter', # This rule is broken and reports false positives
    'PSAvoidUsingComputerNameHardcoded' # Acceptable in test scripts
    'PSAvoidUsingConvertToSecureStringWithPlainText' # Acceptable in test scripts
    'PSAvoidUsingBrokenHashAlgorithms' # SHA1 and MD5 still have plenty of legitimate use cases
  )

  # Enable specific rules globally
  Rules = @{
    PSUseCompatibleSyntax = @{

      # This turns the rule on (setting it to false will turn it off)
      Enable = $true

      # List of targeted PowerShell versions
      TargetVersions = @(
        '5.1',  # Windows PowerShell (legacy)
        '6.1',  # PowerShell Core (first stable)
        '6.2',  # PowerShell Core LTS
        '7.0',  # PowerShell 7 initial release
        '7.1',  # First PowerShell 7 LTS
        '7.2',  # PowerShell 7 LTS
        '7.4',  # PowerShell 7 LTS (current)
        '7.5'   # Latest stable
      )
    }
  }
}
