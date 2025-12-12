function Get-WhichCommand
{
    <#
    .SYNOPSIS
        Locates a command and displays its location or type (mimics POSIX which).

    .DESCRIPTION
        Cross-platform function that mimics the behavior of the POSIX 'which' command.

        Searches for commands in the following order:
        1. PowerShell aliases
        2. PowerShell functions
        3. PowerShell cmdlets
        4. External executables in PATH

        Returns the full path for executables or the definition/type for PowerShell commands.
        Supports multiple command names and pipeline input.

        Aliases:
        The 'which' alias is created only if it doesn't already exist in the current environment.

    .PARAMETER Name
        The name of the command(s) to locate. Accepts multiple values and pipeline input.

    .PARAMETER All
        Display all matches instead of just the first one found.
        Includes the CommandType, Name, Definition, and Source in the output.
        By default, only the first match is returned (mimics POSIX 'which' behavior).

    .EXAMPLE
        PS > Get-WhichCommand git

        C:\Program Files\Git\cmd\git.exe

        Locates the git executable and returns its full path (POSIX which behavior).

    .EXAMPLE
        PS > Get-WhichCommand ls

        ls -> Get-ChildItem

        Shows that 'ls' is an alias for Get-ChildItem.

    .EXAMPLE
        PS > 'git', 'pwsh', 'Get-Process' | Get-WhichCommand

        /opt/homebrew/bin/git
        /usr/local/microsoft/powershell/7/pwsh
        Microsoft.PowerShell.Management

        Locates multiple commands via pipeline input.

    .EXAMPLE
        PS > Get-WhichCommand 'pytho*' -All

        CommandType Name              Definition                          Source
        ----------- ----              ----------                          ------
        Application python3           /usr/bin/python3                    /usr/bin/python3
        Application python3.13        /opt/homebrew/bin/python3.13        /opt/homebrew/bin/python3.13
        Application python3.13-config /opt/homebrew/bin/python3.13-config /opt/homebrew/bin/python3.13-config

        Shows all executables matching 'pytho*' pattern found in PATH.

    .OUTPUTS
        String with command path or definition.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Get-WhichCommand.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Get-WhichCommand.ps1
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Name,

        [Parameter()]
        [Switch]$All
    )

    begin
    {
        Write-Verbose 'Starting Get-WhichCommand'
    }

    process
    {
        foreach ($cmdName in $Name)
        {
            Write-Verbose "Searching for command: $cmdName"
            $found = $false

            try
            {
                # Get all matching commands
                $commands = Get-Command -Name $cmdName -ErrorAction SilentlyContinue

                if (-not $commands)
                {
                    Write-Verbose "Command not found: $cmdName"
                    Write-Warning "Command not found: $cmdName"
                    continue
                }

                # If not using -All, take only the first match (default behavior)
                # This mimics POSIX 'which' which returns the first executable found in PATH
                if (-not $All)
                {
                    $commands = @($commands)[0]
                }

                foreach ($cmd in $commands)
                {
                    $found = $true

                    switch ($cmd.CommandType)
                    {
                        'Alias'
                        {
                            $resolvedCommand = $cmd.ResolvedCommand
                            if ($All)
                            {
                                [PSCustomObject]@{
                                    CommandType = 'Alias'
                                    Name = $cmd.Name
                                    Definition = if ($resolvedCommand) { "$($cmd.Name) -> $($resolvedCommand.Name)" } else { "$($cmd.Name) -> $($cmd.Definition)" }
                                    Source = $cmd.Source
                                }
                            }
                            else
                            {
                                if ($resolvedCommand)
                                {
                                    "$($cmd.Name) -> $($resolvedCommand.Name)"
                                }
                                else
                                {
                                    "$($cmd.Name) -> $($cmd.Definition)"
                                }
                            }
                        }
                        'Function'
                        {
                            if ($All)
                            {
                                [PSCustomObject]@{
                                    CommandType = 'Function'
                                    Name = $cmd.Name
                                    Definition = if ($cmd.ScriptBlock.File) { $cmd.ScriptBlock.File } else { '<ScriptBlock>' }
                                    Source = $cmd.Source
                                }
                            }
                            else
                            {
                                if ($cmd.ScriptBlock.File)
                                {
                                    $cmd.ScriptBlock.File
                                }
                                else
                                {
                                    "$($cmd.Name) (Function)"
                                }
                            }
                        }
                        'Cmdlet'
                        {
                            if ($All)
                            {
                                [PSCustomObject]@{
                                    CommandType = 'Cmdlet'
                                    Name = $cmd.Name
                                    Definition = $cmd.Source
                                    Module = $cmd.ModuleName
                                }
                            }
                            else
                            {
                                if ($cmd.Source)
                                {
                                    $cmd.Source
                                }
                                else
                                {
                                    "$($cmd.Name) (Cmdlet from $($cmd.ModuleName))"
                                }
                            }
                        }
                        'Application'
                        {
                            if ($All)
                            {
                                [PSCustomObject]@{
                                    CommandType = 'Application'
                                    Name = $cmd.Name
                                    Definition = $cmd.Source
                                    Source = $cmd.Source
                                }
                            }
                            else
                            {
                                $cmd.Source
                            }
                        }
                        'ExternalScript'
                        {
                            if ($All)
                            {
                                [PSCustomObject]@{
                                    CommandType = 'ExternalScript'
                                    Name = $cmd.Name
                                    Definition = $cmd.Source
                                    Source = $cmd.Source
                                }
                            }
                            else
                            {
                                $cmd.Source
                            }
                        }
                        default
                        {
                            if ($All)
                            {
                                [PSCustomObject]@{
                                    CommandType = $cmd.CommandType
                                    Name = $cmd.Name
                                    Definition = $cmd.Definition
                                    Source = $cmd.Source
                                }
                            }
                            else
                            {
                                if ($cmd.Source)
                                {
                                    $cmd.Source
                                }
                                else
                                {
                                    $cmd.Definition
                                }
                            }
                        }
                    }
                }

                if (-not $found)
                {
                    Write-Verbose "No results for: $cmdName"
                }
            }
            catch
            {
                Write-Verbose "Error processing command '$cmdName': $($_.Exception.Message)"
                throw $_
            }
        }
    }

    end
    {
        Write-Verbose 'Get-WhichCommand completed'
    }
}

# Create 'which' alias only if the native which command doesn't exist
if (-not (Get-Command -Name 'which' -CommandType Application -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'which' alias for Get-WhichCommand"
        Set-Alias -Name 'which' -Value 'Get-WhichCommand' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Get-WhichCommand: Could not create 'which' alias: $($_.Exception.Message)"
    }
}
