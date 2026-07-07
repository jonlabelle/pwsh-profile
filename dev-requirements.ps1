# Install required PowerShell modules for development, testing, and analysis
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module -Name Pester -MinimumVersion '5.0.0' -MaximumVersion '5.99.99' -Scope CurrentUser -Force -SkipPublisherCheck
