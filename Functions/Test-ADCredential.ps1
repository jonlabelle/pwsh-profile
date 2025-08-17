function Test-ADCredential
{
    <#
    .SYNOPSIS
        Test the username and password of Active Directory credentials.

    .DESCRIPTION
        This function validates Active Directory credentials by attempting to authenticate
        against the Active Directory domain. It returns a boolean value indicating whether
        the authentication was successful. The function includes proper error handling
        and resource cleanup.

        NOTE: This function only works on Windows platforms as it relies on Windows-specific
        .NET DirectoryServices classes and Active Directory integration. On macOS and Linux,
        use alternative LDAP authentication methods.

    .PARAMETER Credential
        The PSCredential object containing username and password to test.
        This parameter is mandatory and accepts pipeline input.

    .EXAMPLE
        PS> $cred = Get-Credential
        PS> Test-ADCredential -Credential $cred
        True

        Tests the credentials provided and returns $true if they are valid.

    .EXAMPLE
        PS> Get-Credential | Test-ADCredential -Verbose
        VERBOSE: Successfully authenticated 'username'
        True

        Tests credentials from the pipeline with verbose output.

    .EXAMPLE
        PS> Test-ADCredential -Credential $invalidCred -Verbose
        VERBOSE: Authentication failed for 'username': Logon failure: unknown user name or bad password
        False

        Tests invalid credentials and shows the detailed error message with verbose output.

    .OUTPUTS
        System.Boolean
        Returns $true if authentication succeeds, otherwise $false.

    .NOTES
        This function attempts to bind to the domain controller using the provided credentials.
        It uses proper exception handling and resource cleanup. Requires the machine to be
        domain-joined or have access to a domain controller.

    .LINK
        https://jonlabelle.com/snippets/view/powershell/test-windows-credential
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]
        $Credential
    )

    process
    {
        # Platform detection
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # PowerShell 5.1 - Windows only
            $script:IsWindowsPlatform = $true
            $script:IsMacOSPlatform = $false
            $script:IsLinuxPlatform = $false
        }
        else
        {
            # PowerShell Core - cross-platform
            $script:IsWindowsPlatform = $IsWindows
            $script:IsMacOSPlatform = $IsMacOS
            $script:IsLinuxPlatform = $IsLinux
        }

        # Check if running on Windows
        if (-not $script:IsWindowsPlatform)
        {
            $platformName = if ($script:IsMacOSPlatform) { 'macOS' } elseif ($script:IsLinuxPlatform) { 'Linux' } else { 'this platform' }
            throw "Test-ADCredential is only supported on Windows. On $platformName, use alternative LDAP authentication methods or consider using PowerShell modules like 'Microsoft.Graph' for Azure AD authentication."
        }

        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password

        try
        {
            # Get the domain distinguished name more reliably
            $rootDSE = New-Object System.DirectoryServices.DirectoryEntry('LDAP://RootDSE')
            $defaultNamingContext = $rootDSE.Properties['defaultNamingContext'][0]
            $domain = "LDAP://$defaultNamingContext"
            $rootDSE.Dispose()
        }
        catch
        {
            Write-Warning 'Unable to determine domain context. Using current domain.'
            try
            {
                $domain = 'LDAP://' + ([ADSI]'').distinguishedName
            }
            catch
            {
                Write-Error 'Unable to connect to Active Directory. Ensure you are on a domain-joined machine.'
                return $false
            }
        }

        $de = $null
        try
        {
            $de = New-Object System.DirectoryServices.DirectoryEntry($domain, $username, $password)

            # Force authentication by accessing a property
            $null = $de.Name

            Write-Verbose "Successfully authenticated '$username'"
            $true
        }
        catch [System.DirectoryServices.DirectoryServiceCOMException]
        {
            Write-Verbose "Authentication failed for '$username': $($_.Exception.Message)"
            $false
        }
        catch
        {
            Write-Error "Unexpected error during authentication: $($_.Exception.Message)"
            $false
        }
        finally
        {
            if ($null -ne $de)
            {
                $de.Dispose()
            }
        }
    }
}
