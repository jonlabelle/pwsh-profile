function Test-ADCredential
{
    <#
    .SYNOPSIS
        Test the username and password of Active Directory credentials.

    .DESCRIPTION
        This function validates Active Directory credentials by attempting to authenticate
        against the Active Directory domain controller. It supports both simple name-based
        validation and thorough directory queries to ensure credentials are properly
        authenticated.

        REQUIREMENTS:
        - Windows platform (relies on Windows-specific .NET DirectoryServices classes)
        - Active connection to an Active Directory domain controller
        - Network access to query the domain

        NOTE: This function only works on Windows platforms. On macOS and Linux, use
        alternative LDAP authentication methods or PowerShell modules like 'Microsoft.Graph'
        for Azure AD authentication.

    .PARAMETER Credential
        The PSCredential object containing username and password to test.
        This parameter is mandatory and accepts pipeline input.

    .EXAMPLE
        PS> $cred = Get-Credential
        PS> Test-ADCredential -Credential $cred
        Successfully authenticated with 'username'
        True

        Tests the credentials provided and returns $true if they are valid.

    .EXAMPLE
        PS> Get-Credential | Test-ADCredential -Verbose
        VERBOSE: Successfully authenticated 'username'
        Successfully authenticated with 'username'
        True

        Tests credentials from the pipeline with verbose output.

    .EXAMPLE
        PS> Test-ADCredential -Credential $invalidCred -Verbose
        VERBOSE: Authentication failed for 'username': Unable to bind to directory
        Authentication failed for 'username'
        False

        Tests invalid credentials and shows the detailed error message with verbose output.

    .OUTPUTS
        System.Boolean
        Returns $true if authentication succeeds, otherwise $false.

    .NOTES
        This function validates credentials by first attempting a simple directory binding
        test, then performing a directory search to ensure comprehensive validation.
        It includes proper error handling and resource cleanup for all DirectoryServices
        objects.

    .LINK
        https://jonlabelle.com/snippets/view/powershell/test-active-directory-credential
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]
        $Credential
    )

    begin
    {
        # Load required assemblies for DirectoryServices
        try
        {
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction Stop
            Add-Type -AssemblyName System.DirectoryServices -ErrorAction Stop
        }
        catch
        {
            Write-Warning "Failed to load DirectoryServices assemblies: $($_.Exception.Message)"
        }
    }

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
            Write-Error 'Unable to connect to Active Directory. This function requires a connection to an Active Directory domain controller. Ensure you are on a domain-joined machine or have network access to a domain controller.'
            return $false
        }

        $de = $null
        try
        {
            $de = New-Object System.DirectoryServices.DirectoryEntry($domain, $username, $password)

            # Test authentication using the original simpler approach first
            if ($null -eq $de.Name)
            {
                Write-Verbose "Authentication failed for '$username': Unable to bind to directory"
                Write-Host "Authentication failed for '$username'" -ForegroundColor Red
                return $false
            }

            # If simple test passes, perform more thorough validation
            # Just accessing .Name isn't sufficient - we need to actually query the directory
            $searcher = New-Object System.DirectoryServices.DirectorySearcher($de)
            $searcher.Filter = '(objectClass=*)'
            $searcher.SizeLimit = 1
            $null = $searcher.FindOne()
            $searcher.Dispose()

            Write-Verbose "Successfully authenticated '$username'"
            Write-Host "Successfully authenticated with '$username'" -ForegroundColor Green
            $true
        }
        catch [System.Runtime.InteropServices.COMException]
        {
            # Handle COM exceptions from DirectoryServices operations
            Write-Verbose "Authentication failed for '$username': $($_.Exception.Message)"
            Write-Host "Authentication failed for '$username'" -ForegroundColor Red
            $false
        }
        catch [System.DirectoryServices.DirectoryServiceCOMException]
        {
            # Handle DirectoryServices specific exceptions if available
            Write-Verbose "Authentication failed for '$username': $($_.Exception.Message)"
            Write-Host "Authentication failed for '$username'" -ForegroundColor Red
            $false
        }
        catch
        {
            Write-Verbose "Authentication failed for '$username': $($_.Exception.Message)"
            Write-Host "Authentication failed for '$username'" -ForegroundColor Red
            $false
        }
        finally
        {
            if ($null -ne $de)
            {
                try
                {
                    $de.Dispose()
                }
                catch
                {
                    # Silently ignore disposal errors as the object may already be disposed
                    Write-Debug "DirectoryEntry disposal failed: $($_.Exception.Message)"
                }
            }
        }
    }
}
