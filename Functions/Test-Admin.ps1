function Test-Admin
{
    <#
    .SYNOPSIS
        Determines if the console is elevated.

    .LINK
        https://jonlabelle.com/snippets/view/powershell/check-if-the-current-user-is-an-administrator
    #>
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
