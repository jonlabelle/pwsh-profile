function Get-CmdletAlias
{
    <#
    .SYNOPSIS
        Lists all aliases for the specified cmdlet.

    .DESCRIPTION
        This function retrieves and displays all defined aliases that reference a specific cmdlet.
        It helps users discover alternative shorthand ways to call frequently used cmdlets.
        Supports wildcard patterns for flexible cmdlet name matching.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER CmdletName
        The name of the cmdlet to find aliases for. Can be a partial name (wildcards are supported).
        This parameter is mandatory and supports pipeline input.

    .EXAMPLE
        PS> Get-CmdletAlias -CmdletName Get-ChildItem

        Definition    Name
        ----------    ----
        Get-ChildItem dir
        Get-ChildItem gci
        Get-ChildItem ls

        Lists all aliases defined for the Get-ChildItem cmdlet.

    .EXAMPLE
        PS> Get-CmdletAlias -CmdletName Select*

        Definition    Name
        ----------    ----
        Select-Object select
        Select-String sls

        Lists all aliases for cmdlets that start with "Select".

    .EXAMPLE
        PS> 'Get-Process', 'Get-Service' | Get-CmdletAlias

        Definition  Name
        ----------  ----
        Get-Process gps
        Get-Process ps
        Get-Service gsv

        Gets aliases for multiple cmdlets using pipeline input.

    .OUTPUTS
        System.Object
        A formatted table showing the cmdlet definition and its corresponding aliases.

    .NOTES
        This function is commonly added to PowerShell profiles for quick alias reference.
        Compatible with PowerShell Desktop 5.1+ and PowerShell Core 6+.
        Works on Windows, macOS, and Linux.

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
        $CmdletName
    )

    begin
    {
        Write-Verbose 'Starting cmdlet alias lookup'
    }

    process
    {
        Write-Verbose "Looking up aliases for cmdlet: '$CmdletName'"

        try
        {
            $aliases = Get-Alias | Where-Object -FilterScript { $_.Definition -like "$CmdletName" }

            if ($aliases)
            {
                Write-Verbose "Found $($aliases.Count) alias(es) for '$CmdletName'"
                $aliases | Format-Table -Property Definition, Name -AutoSize
            }
            else
            {
                Write-Verbose "No aliases found for cmdlet: '$CmdletName'"
                Write-Warning "No aliases found for cmdlet: '$CmdletName'"
            }
        }
        catch
        {
            Write-Verbose "Error occurred while looking up aliases: $($_.Exception.Message)"
            throw $_
        }
    }

    end
    {
        Write-Verbose 'Cmdlet alias lookup completed'
    }
}
