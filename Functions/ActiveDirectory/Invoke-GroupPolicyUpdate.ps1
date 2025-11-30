function Invoke-GroupPolicyUpdate
{
    <#
    .SYNOPSIS
        Forces an immediate Group Policy update on Windows systems.

    .DESCRIPTION
        This function executes the `gpupdate /force` command to immediately refresh both
        Computer and User Group Policy settings on a Windows system. This is useful when
        you need to apply new or modified Group Policy settings without waiting for the
        automatic refresh interval.

        The function automatically requests elevation (UAC prompt) to ensure both Computer
        and User policies are updated. This uses the Invoke-ElevatedCommand function for
        reliable elevation handling, including support for PIM/Elevated Admin roles.

        REQUIREMENTS:
        - Windows platform only (gpupdate.exe is a Windows-specific utility)
        - User must accept UAC prompt for elevation
        - Active Directory domain environment

        PLATFORM COMPATIBILITY:
        This function is Windows-only. It will return an error on macOS and Linux platforms.

        NOTES:
        - Always prompts for elevation via UAC to ensure full policy updates
        - Computer Policy updates require Administrator privileges
        - The process may take several minutes depending on policy complexity
        - Network connectivity to domain controllers is required

    .EXAMPLE
        PS > Invoke-GroupPolicyUpdate

        Forcing Group Policy update with elevated privileges...
        User Policy update has completed successfully.
        Computer Policy update has completed successfully.
        Group Policy update completed successfully.

        Forces an immediate Group Policy update with elevation, displaying output.

    .EXAMPLE
        PS > Invoke-GroupPolicyUpdate -Verbose

        VERBOSE: Checking platform compatibility
        VERBOSE: Requesting elevated privileges for Group Policy update
        Forcing Group Policy update with elevated privileges...
        VERBOSE: Executing gpupdate /force with elevation
        User Policy update has completed successfully.
        Computer Policy update has completed successfully.
        VERBOSE: Group Policy update completed successfully
        Group Policy update completed successfully.

        Forces a Group Policy update with verbose output showing detailed progress.

    .OUTPUTS
        None

    .NOTES
        This function uses Invoke-ElevatedCommand to ensure proper elevation, which handles
        complex scenarios like PIM (Privileged Identity Management) and elevated admin roles
        more reliably than simple administrator checks.

        DEPENDENCIES:
        - Invoke-ElevatedCommand function (Functions/SystemAdministration/Invoke-ElevatedCommand.ps1)

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ActiveDirectory/Invoke-GroupPolicyUpdate.ps1

    .LINK
        https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/gpupdate
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    param()

    begin
    {
        # Helper function to load dependencies on demand
        function Import-DependencyIfNeeded
        {
            param(
                [Parameter(Mandatory)]
                [String]$FunctionName,

                [Parameter(Mandatory)]
                [String]$RelativePath
            )

            if (-not (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue))
            {
                Write-Verbose "$FunctionName is required - attempting to load it"

                # Resolve path from current script location
                $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
                $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

                if (Test-Path -Path $dependencyPath -PathType Leaf)
                {
                    try
                    {
                        . $dependencyPath
                        Write-Verbose "Loaded $FunctionName from: $dependencyPath"
                    }
                    catch
                    {
                        throw "Failed to load required dependency '$FunctionName' from '$dependencyPath': $($_.Exception.Message)"
                    }
                }
                else
                {
                    throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
                }
            }
            else
            {
                Write-Verbose "$FunctionName is already loaded"
            }
        }

        Write-Verbose 'Checking platform compatibility'

        # Platform detection for PowerShell 5.1 and Core
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # PowerShell 5.1 - Windows only
            $script:IsWindowsPlatform = $true
        }
        else
        {
            # PowerShell Core - use built-in variables
            $script:IsWindowsPlatform = $IsWindows
        }

        # Verify Windows platform
        if (-not $script:IsWindowsPlatform)
        {
            throw 'This function is only supported on Windows platforms. Group Policy is a Windows-specific feature.'
        }

        # Load Invoke-ElevatedCommand dependency
        Import-DependencyIfNeeded -FunctionName 'Invoke-ElevatedCommand' -RelativePath '..\SystemAdministration\Invoke-ElevatedCommand.ps1'
    }

    process
    {
        try
        {
            Write-Host 'Forcing Group Policy update with elevated privileges...' -ForegroundColor Cyan
            Write-Verbose 'Requesting elevated privileges for Group Policy update'

            # Use Invoke-ElevatedCommand to ensure proper elevation
            # This handles PIM/Elevated Admin roles and UAC properly
            Invoke-ElevatedCommand -Scriptblock {
                Write-Verbose 'Executing gpupdate /force with elevation'

                # Execute gpupdate /force
                $process = Start-Process -FilePath 'gpupdate.exe' -ArgumentList '/force' -NoNewWindow -Wait -PassThru

                # Return the exit code and any output
                [PSCustomObject]@{
                    ExitCode = $process.ExitCode
                    Success = ($process.ExitCode -eq 0)
                }
            } | ForEach-Object {
                Write-Verbose "Group Policy update completed with exit code: $($_.ExitCode)"

                if ($_.Success)
                {
                    Write-Host 'Group Policy update completed successfully.' -ForegroundColor Green
                }
                else
                {
                    Write-Warning "Group Policy update completed with exit code: $($_.ExitCode). Some policies may not have been applied."
                }
            }
        }
        catch
        {
            Write-Error "Failed to execute Group Policy update: $($_.Exception.Message)"
            throw $_
        }
    }

    end
    {
        Write-Verbose 'Group Policy update function completed'
    }
}
