# PSScriptAnalyzerSettings.psd1
#
# Settings for PSScriptAnalyzer invocation.
# All default rules are also enabled.
#
# Example usage:
# Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1 -Path . -Recurse
@{
  # Exclude specific rules globally
  ExcludeRules = @(
    'PSAvoidUsingWriteHost',
    'PSUseShouldProcessForStateChangingFunctions',
    'PSAvoidGlobalVars',
    'PSReviewUnusedParameter' # This rule is broken and reports false positives
  )

  Rules = @{
    PSUseCompatibleSyntax = @{

      # This turns the rule on (setting it to false will turn it off)
      Enable = $true

      # Simply list the targeted versions of PowerShell here
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
