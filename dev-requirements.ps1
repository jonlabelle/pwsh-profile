# Install required PowerShell modules for development, testing, and analysis
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
if ($PSVersionTable.PSEdition -eq 'Desktop' -and $PSVersionTable.PSVersion.Major -eq 5)
{
    Install-Module -Name Pester -MinimumVersion '5.0.0' -MaximumVersion '5.99.99' -Scope CurrentUser -Force -SkipPublisherCheck
}
else
{
    Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck
}
