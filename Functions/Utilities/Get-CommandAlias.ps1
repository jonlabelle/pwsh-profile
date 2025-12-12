function Get-CommandAlias
{
    <#
    .SYNOPSIS
        Lists all aliases for the specified PowerShell command.

    .DESCRIPTION
        This function retrieves and displays all defined aliases that reference a specific command,
        or resolves an alias to its underlying command definition.
        It helps users discover alternative shorthand ways to call frequently used commands.
        Supports wildcard patterns for flexible command name matching.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Name
        The name of the command to find aliases for, or the alias name to resolve (when using -Reverse).
        Can be a partial name (wildcards are supported).
        This parameter is mandatory and supports pipeline input.

    .PARAMETER Reverse
        When specified, resolves the alias to its command definition instead of finding aliases for a command.

    .EXAMPLE
        PS > Get-CommandAlias -Name Get-ChildItem

        Definition    Name
        ----------    ----
        Get-ChildItem dir
        Get-ChildItem gci
        Get-ChildItem ls

        Lists all aliases defined for the Get-ChildItem command.

    .EXAMPLE
        PS > Get-CommandAlias -Name Select*

        Definition    Name
        ----------    ----
        Select-Object select
        Select-String sls

        Lists all aliases for commands that start with "Select".

    .EXAMPLE
        PS > 'Get-Process', 'Get-Service' | Get-CommandAlias

        Definition  Name
        ----------  ----
        Get-Process gps
        Get-Process ps
        Get-Service gsv

        Gets aliases for multiple commands using pipeline input.

    .EXAMPLE
        PS > Get-CommandAlias -Name ls -Reverse

        CommandType Name          Definition
        ----------- ----          ----------
        Alias       ls            Get-ChildItem

        Resolves the 'ls' alias to show it points to Get-ChildItem.

    .EXAMPLE
        PS > 'gci', 'ps', 'gsv' | Get-CommandAlias -Reverse

        CommandType Name Definition
        ----------- ---- ----------
        Alias       gci  Get-ChildItem
        Alias       ps   Get-Process
        Alias       gsv  Get-Service

        Resolves multiple aliases using pipeline input.

    .OUTPUTS
        System.Object
        A formatted table showing the command definition and its corresponding aliases.

    .NOTES
        This function is commonly added to PowerShell profiles for quick alias reference.
        Compatible with PowerShell Desktop 5.1+ and PowerShell Core 6+.
        Works on Windows, macOS, and Linux.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Get-CommandAlias.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Get-CommandAlias.ps1

    .LINK
        https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles

    .LINK
        https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.2#add-a-function-that-lists-the-aliases-for-any-cmdlet
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Name,

        [Parameter()]
        [Switch]
        $Reverse
    )

    begin
    {
        if ($Reverse)
        {
            Write-Verbose 'Starting alias resolution'
        }
        else
        {
            Write-Verbose 'Starting cmdlet alias lookup'
        }
    }

    process
    {
        try
        {
            if ($Reverse)
            {
                Write-Verbose "Resolving alias: '$Name'"

                $resolvedAlias = Get-Alias -Name $Name -ErrorAction SilentlyContinue

                if ($resolvedAlias)
                {
                    Write-Verbose "Alias '$Name' resolves to: $($resolvedAlias.Definition)"
                    $resolvedAlias | Format-Table -Property CommandType, Name, Definition -AutoSize
                }
                else
                {
                    Write-Verbose "No alias found with name: '$Name'"
                    Write-Warning "No alias found with name: '$Name'"
                }
            }
            else
            {
                Write-Verbose "Looking up aliases for cmdlet: '$Name'"

                $aliases = Get-Alias | Where-Object -FilterScript { $_.Definition -like "$Name" }

                if ($aliases)
                {
                    Write-Verbose "Found $($aliases.Count) alias(es) for '$Name'"
                    $aliases | Format-Table -Property Definition, Name -AutoSize
                }
                else
                {
                    Write-Verbose "No aliases found for cmdlet: '$Name'"
                    Write-Warning "No aliases found for cmdlet: '$Name'"
                }
            }
        }
        catch
        {
            Write-Verbose "Error occurred: $($_.Exception.Message)"
            throw $_
        }
    }

    end
    {
        if ($Reverse)
        {
            Write-Verbose 'Alias resolution completed'
        }
        else
        {
            Write-Verbose 'Cmdlet alias lookup completed'
        }
    }
}
