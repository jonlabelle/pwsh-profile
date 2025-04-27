function Test-ADCredential
{
    <#
    .SYNOPSIS
        Test the username and password of Active Directory credentials.

    .DESCRIPTION
        This function validates Active Directory credentials by attempting to authenticate
        against the Active Directory domain. It returns a boolean value indicating whether
        the authentication was successful.

    .PARAMETER Credential
        The PSCredential object containing username and password to test.
        This parameter is mandatory and accepts pipeline input.

    .EXAMPLE
        PS> $cred = Get-Credential
        PS> Test-ADCredential -Credential $cred
        Successfully authenticated 'username'
        True

        Tests the credentials provided and returns $true if they are valid.

    .EXAMPLE
        PS> Get-Credential | Test-ADCredential
        Authentication failed for 'username'
        False

        Tests credentials from the pipeline and returns $false if authentication fails.

    .OUTPUTS
        System.Boolean
        Returns $true if authentication succeeds, otherwise $false.

    .NOTES
        This function attempts to bind to the default domain controller using the provided credentials.
        If authentication fails, it writes an error message but continues execution.

    .LINK
        https://jonlabelle.com/snippets/view/powershell/test-windows-credential
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
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
        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password
        $domain = 'LDAP://' + ([ADSI]'').distinguishedName

        $de = New-Object System.DirectoryServices.DirectoryEntry($domain, $username, $password)

        if ($null -eq $de.name)
        {
            Write-Error "Authentication failed for '$username'"
            $false
        }
        else
        {
            Write-Host "Successfully authenticated '$username'" -ForegroundColor Green
            $true
        }

        $de.Dispose()
    }
}
