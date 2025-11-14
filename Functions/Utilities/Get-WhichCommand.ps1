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
        The 'which' and 'where' aliases are created only if they don't already exist in the
        current environment (i.e., no native commands with those names are found in PATH).

    .PARAMETER Name
        The name of the command(s) to locate. Accepts multiple values and pipeline input.

    .PARAMETER All
        Display all matches instead of just the first one found.

    .EXAMPLE
        PS > Get-WhichCommand git

        C:\Program Files\Git\cmd\git.exe

        Locates the git executable in PATH.

    .EXAMPLE
        PS > Get-WhichCommand ls

        CommandType     Name                           Definition
        -----------     ----                           ----------
        Alias           ls -> Get-ChildItem

        Shows that 'ls' is an alias for Get-ChildItem.

    .EXAMPLE
        PS > 'git', 'pwsh', 'Get-Process' | Get-WhichCommand

        Locates multiple commands via pipeline input.

    .EXAMPLE
        PS > Get-WhichCommand python -All

        C:\Python39\python.exe
        C:\Python310\python.exe

        Shows all python executables found in PATH.

    .OUTPUTS
        PSCustomObject with command details, or string for simple executable paths.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [String])]
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

                # If not using -All, take only the first match
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
                            $definition = if ($resolvedCommand)
                            {
                                "$($cmd.Name) -> $($resolvedCommand.Name)"
                            }
                            else
                            {
                                "$($cmd.Name) -> $($cmd.Definition)"
                            }

                            [PSCustomObject]@{
                                CommandType = 'Alias'
                                Name = $cmdName
                                Definition = $definition
                                Source = $cmd.Source
                            }
                        }
                        'Function'
                        {
                            [PSCustomObject]@{
                                CommandType = 'Function'
                                Name = $cmd.Name
                                Definition = if ($cmd.ScriptBlock.File)
                                {
                                    $cmd.ScriptBlock.File
                                }
                                else
                                {
                                    '<ScriptBlock>'
                                }
                                Source = $cmd.Source
                            }
                        }
                        'Cmdlet'
                        {
                            [PSCustomObject]@{
                                CommandType = 'Cmdlet'
                                Name = $cmd.Name
                                Definition = $cmd.Source
                                Module = $cmd.ModuleName
                            }
                        }
                        'Application'
                        {
                            # For executables, just return the path (like POSIX which)
                            $cmd.Source
                        }
                        'ExternalScript'
                        {
                            # PowerShell scripts
                            $cmd.Source
                        }
                        default
                        {
                            [PSCustomObject]@{
                                CommandType = $cmd.CommandType
                                Name = $cmd.Name
                                Definition = $cmd.Definition
                                Source = $cmd.Source
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
    Set-Alias -Name 'which' -Value 'Get-WhichCommand' -Scope Global
}

# Create 'where' (Windows command-prompt) alias only if the native where command doesn't exist
if (-not (Get-Command -Name 'where' -CommandType Application -ErrorAction SilentlyContinue))
{
    Set-Alias -Name 'where' -Value 'Get-WhichCommand' -Scope Global
}
