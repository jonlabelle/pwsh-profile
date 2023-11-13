function Test-ADCredential
{
    <#
    .SYNOPSIS
        Test the username and password of Active Directory credentials.

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
