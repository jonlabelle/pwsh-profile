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
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]
        $Credential
    )

    process
    {
        $user = $Credential.username
        $password = $Credential.GetNetworkCredential().password

        $domain = 'LDAP://' + ([ADSI]'').distinguishedName
        $de = New-Object System.DirectoryServices.DirectoryEntry($domain, $user, $password)

        if ($null -eq $de.name)
        {
            Write-Error "Authentication failed for '$user'"
        }
        else
        {
            Write-Host "Successfully authenticated with '$user'" -ForegroundColor Green
        }

        $de.Dispose()
    }
}
