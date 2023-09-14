function Update-AllModules
{
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
