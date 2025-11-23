function Test-ADUserLocked
{
    <#
    .SYNOPSIS
        Test if an Active Directory user account is locked out.

    .DESCRIPTION
        This function checks if an Active Directory user account is currently locked out
        by querying the user's lockoutTime attribute. It uses the Windows DirectoryServices
        classes to perform the query without requiring additional modules or dependencies.

        REQUIREMENTS:
        - Windows platform (relies on Windows-specific .NET DirectoryServices classes)
        - Active connection to an Active Directory domain controller
        - Network access to query the domain
        - Sufficient permissions to read user account attributes

        NOTE: This function only works on Windows platforms. On macOS and Linux, use
        alternative LDAP authentication methods or PowerShell modules like 'Microsoft.Graph'
        for Azure AD queries.

    .PARAMETER UserName
        The username (sAMAccountName) of the Active Directory user to check.
        This parameter is mandatory and accepts pipeline input.

    .PARAMETER Domain
        Optional domain name to search. If not specified, uses the current domain.

    .EXAMPLE
        PS > Test-ADUserLocked -UserName 'jdoe'
        User 'jdoe' is not locked out
        False

        Tests if user 'jdoe' is locked out and returns $false if the account is not locked.

    .EXAMPLE
        PS > Test-ADUserLocked -UserName 'lockeduser' -Verbose
        VERBOSE: Searching for user 'lockeduser' in domain
        VERBOSE: User found with lockoutTime: 133456789012345678
        VERBOSE: Account lockout detected for 'lockeduser'
        User 'lockeduser' is locked out
        True

        Tests a locked user account with verbose output showing the lockout detection.

    .EXAMPLE
        PS > 'user1', 'user2', 'user3' | Test-ADUserLocked
        User 'user1' is not locked out
        User 'user2' is locked out
        User 'user3' is not locked out
        False
        True
        False

        Tests multiple users from the pipeline and returns their lockout status.

    .OUTPUTS
        System.Boolean
        Returns $true if the user account is locked out, otherwise $false.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ActiveDirectory/Test-ADUserLocked.ps1

        The function checks the lockoutTime attribute in Active Directory. A value greater
        than 0 indicates the account is locked out. The function includes proper error
        handling and resource cleanup for all DirectoryServices objects.

        Requires permissions to read user attributes in Active Directory.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$UserName,

        [Parameter()]
        [String]$Domain
    )

    begin
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
            throw "Test-ADUserLocked is only supported on Windows. On $platformName, use alternative LDAP authentication methods or consider using PowerShell modules like 'Microsoft.Graph' for Azure AD queries."
        }

        # Load required assemblies for DirectoryServices
        try
        {
            Add-Type -AssemblyName System.DirectoryServices -ErrorAction Stop
        }
        catch
        {
            throw "Failed to load DirectoryServices assembly: $($_.Exception.Message)"
        }

        # Get domain information once in begin block
        try
        {
            if ($Domain)
            {
                $domainPath = "LDAP://$Domain"
            }
            else
            {
                $rootDSE = New-Object System.DirectoryServices.DirectoryEntry('LDAP://RootDSE')
                $defaultNamingContext = $rootDSE.Properties['defaultNamingContext'][0]
                $domainPath = "LDAP://$defaultNamingContext"
                $rootDSE.Dispose()
            }
            Write-Verbose "Using domain path: $domainPath"
        }
        catch
        {
            throw 'Unable to connect to Active Directory. This function requires a connection to an Active Directory domain controller. Ensure you are on a domain-joined machine or have network access to a domain controller.'
        }
    }

    process
    {
        $directoryEntry = $null
        $searcher = $null

        try
        {
            Write-Verbose "Searching for user '$UserName' in domain"

            # Create directory entry for the domain
            $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry($domainPath)

            # Create searcher to find the user
            $searcher = New-Object System.DirectoryServices.DirectorySearcher($directoryEntry)
            $searcher.Filter = "(&(objectClass=user)(sAMAccountName=$UserName))"
            $searcher.PropertiesToLoad.Add('lockoutTime') | Out-Null
            $searcher.PropertiesToLoad.Add('sAMAccountName') | Out-Null
            $searcher.SizeLimit = 1

            # Search for the user
            $result = $searcher.FindOne()

            if ($null -eq $result)
            {
                Write-Warning "User '$UserName' not found in Active Directory"
                Write-Host "User '$UserName' not found" -ForegroundColor Yellow
                return $false
            }

            # Check lockoutTime attribute
            $lockoutTime = $result.Properties['lockoutTime']

            if ($null -eq $lockoutTime -or $lockoutTime.Count -eq 0)
            {
                Write-Verbose "No lockoutTime attribute found for user '$UserName'"
                Write-Host "User '$UserName' is not locked out" -ForegroundColor Green
                return $false
            }

            # Get the lockout time value
            $lockoutTimeValue = [long]$lockoutTime[0]
            Write-Verbose "User found with lockoutTime: $lockoutTimeValue"

            # A lockoutTime greater than 0 indicates the account is locked
            if ($lockoutTimeValue -gt 0)
            {
                Write-Verbose "Account lockout detected for '$UserName'"
                Write-Host "User '$UserName' is locked out" -ForegroundColor Red
                return $true
            }
            else
            {
                Write-Verbose "No active lockout for '$UserName'"
                Write-Host "User '$UserName' is not locked out" -ForegroundColor Green
                return $false
            }

        }
        catch [System.DirectoryServices.DirectoryServiceCOMException]
        {
            Write-Verbose "DirectoryServices error for '$UserName': $($_.Exception.Message)"
            Write-Host "Error checking lockout status for '$UserName'" -ForegroundColor Red
            return $false
        }
        catch [System.Runtime.InteropServices.COMException]
        {
            Write-Verbose "COM error for '$UserName': $($_.Exception.Message)"
            Write-Host "Error checking lockout status for '$UserName'" -ForegroundColor Red
            return $false
        }
        catch
        {
            Write-Verbose "Unexpected error for '$UserName': $($_.Exception.Message)"
            Write-Host "Error checking lockout status for '$UserName'" -ForegroundColor Red
            return $false
        }
        finally
        {
            # Clean up resources
            if ($null -ne $searcher)
            {
                try
                {
                    $searcher.Dispose()
                }
                catch
                {
                    Write-Debug "DirectorySearcher disposal failed: $($_.Exception.Message)"
                }
            }
            if ($null -ne $directoryEntry)
            {
                try
                {
                    $directoryEntry.Dispose()
                }
                catch
                {
                    Write-Debug "DirectoryEntry disposal failed: $($_.Exception.Message)"
                }
            }
        }
    }
}
