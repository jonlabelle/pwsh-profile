function Update-AllModules
{
    <#
    .SYNOPSIS
        Updates all installed PowerShell modules to their latest versions.

    .DESCRIPTION
        This function updates all installed PowerShell modules to their latest versions from the PowerShell Gallery.
        It's a wrapper around the Update-Module cmdlet with the -Verbose parameter.

    .EXAMPLE
        PS> Update-AllModules
        Updates all installed PowerShell modules to their latest versions with verbose output.

    .NOTES
        It's recommended to trust the PSGallery repository before running this function:
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

        To uninstall old Azure modules:
        Get-InstalledModule -Name 'Azure*' | Uninstall-Module -Verbose

    .LINK
        https://jonlabelle.com/snippets/view/markdown/powershellget-commands
    #>

    # [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    # (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

    # Trust PSGallery (PowerShell Gallery) repository:
    # Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    # Uninstall old Azure modules:
    # Get-InstalledModule -Name 'Azure*' | Uninstall-Module -Verbose

    # Update all PowerShell modules at once.
    # https://jonlabelle.com/snippets/view/markdown/powershellget-commands

    Update-Module -Verbose
}
