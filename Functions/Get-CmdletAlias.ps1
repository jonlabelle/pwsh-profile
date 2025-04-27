function Get-CmdletAlias ($CmdletName)
{
    <#
    .SYNOPSIS
        Lists all aliases for the specified cmdlet.

    .DESCRIPTION
        This function retrieves and displays all defined aliases that reference a specific cmdlet.
        It helps users discover alternative shorthand ways to call frequently used cmdlets.

    .PARAMETER CmdletName
        The name of the cmdlet to find aliases for. Can be a partial name (wildcards are supported).

    .EXAMPLE
        PS> Get-CmdletAlias Get-ChildItem

        Definition  Name
        ----------  ----
        Get-ChildItem dir
        Get-ChildItem gci
        Get-ChildItem ls

        Lists all aliases defined for the Get-ChildItem cmdlet.

    .EXAMPLE
        PS> Get-CmdletAlias Select

        Definition       Name
        ----------       ----
        Select-Object    select
        Select-String    sls

        Lists all aliases for cmdlets that contain "Select" in their name.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        A formatted table showing the cmdlet definition and its corresponding aliases.

    .NOTES
        This function is commonly added to PowerShell profiles for quick alias reference.
        Source: Microsoft PowerShell documentation

    .LINK
        https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles
    #>
    # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.2#add-a-function-that-lists-the-aliases-for-any-cmdlet
    Get-Alias |
    Where-Object -FilterScript {$_.Definition -like "$CmdletName"} |
    Format-Table -Property Definition, Name -AutoSize
}
