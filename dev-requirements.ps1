# Install required PowerShell modules for development, testing, and analysis
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module -Name Pester -MinimumVersion '6.0.0' -MaximumVersion '6.999.999' -Scope CurrentUser -Force -SkipPublisherCheck
