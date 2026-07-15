# Install required PowerShell modules for development, testing, and analysis
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module -Name Pester -MinimumVersion '6.0.0' -Scope CurrentUser -Force -SkipPublisherCheck
