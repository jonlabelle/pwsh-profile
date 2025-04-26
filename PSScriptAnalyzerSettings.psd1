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
    'PSUseShouldProcessForStateChangingFunctions'
  )

  Rules = @{
    PSUseCompatibleSyntax = @{

      # This turns the rule on (setting it to false will turn it off)
      Enable = $true

      # Simply list the targeted versions of PowerShell here
      TargetVersions = @(
        '5.1',
        '6.2',
        '7.0'
      )
    }
  }
}
