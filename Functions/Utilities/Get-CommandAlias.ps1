function Get-CommandAlias
{
    <#
    .SYNOPSIS
        Lists all aliases for the specified PowerShell command.

    .DESCRIPTION
        This function retrieves and displays all defined aliases that reference a specific command.
        It helps users discover alternative shorthand ways to call frequently used commands.
        Supports wildcard patterns for flexible command name matching.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Name
        The name of the command to find aliases for. Can be a partial name (wildcards are supported).
        This parameter is mandatory and supports pipeline input.

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

    .OUTPUTS
        System.Object
        A formatted table showing the command definition and its corresponding aliases.

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
        $Name
    )

    begin
    {
        Write-Verbose 'Starting cmdlet alias lookup'
    }

    process
    {
        Write-Verbose "Looking up aliases for cmdlet: '$Name'"

        try
        {
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
