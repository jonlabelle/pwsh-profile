function Show-ProfileFunctions
{
    <#
    .SYNOPSIS
        Shows a bulleted list of all available functions in the PowerShell profile Functions folder.

    .DESCRIPTION
        This function scans the Functions folder and extracts the SYNOPSIS from each PowerShell function file
        to display a simple bulleted list of available functions with their descriptions.
        Helps users discover what functions are available in their profile.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .EXAMPLE
        PS > Show-ProfileFunctions

        - Convert-LineEndings - Converts line endings between LF (Unix) and CRLF (Windows) with optional file...
        - Copy-DirectoryWithExclusions - Copies a directory recursively with the ability to exclude specific directories.
        - Get-CertificateDetails - Gets detailed SSL/TLS certificate information from remote hosts.
        - Get-CertificateExpiration - Gets the expiration date of an SSL/TLS certificate from a remote host.
        - Get-CommandAlias - Lists all aliases for the specified PowerShell command.
        ...
        ...

        Displays all available profile functions with brief descriptions.

    .OUTPUTS
        System.String
        Formatted list of functions and descriptions

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ProfileManagement/Show-ProfileFunctions.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    [OutputType([String])]
    param()

    begin
    {
        Write-Verbose 'Starting Show-ProfileFunctions'

        # Get the Functions directory path relative to the profile script
        $profilePath = $PROFILE
        if (-not $profilePath)
        {
            $profilePath = $PSCommandPath
        }

        $functionsPath = Join-Path (Split-Path $profilePath -Parent) 'Functions'

        if (-not (Test-Path $functionsPath))
        {
            Write-Warning "Functions directory not found at: $functionsPath"
            return
        }

        Write-Verbose "Scanning Functions directory: $functionsPath"
    }

    process
    {
        try
        {
            # Get all PowerShell files in the Functions directory and subdirectories
            $functionFiles = Get-ChildItem -Path $functionsPath -Filter '*.ps1' -File -Recurse | Sort-Object Name

            if (-not $functionFiles)
            {
                Write-Warning 'No PowerShell function files found in Functions directory'
                return
            }

            Write-Host '' # Blank line for spacing

            foreach ($file in $functionFiles)
            {
                $functionName = ''
                $synopsis = ''

                try
                {
                    # Use PowerShell's AST parser to reliably get function info
                    $tokens = $null
                    $errors = $null
                    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)

                    if ($errors.Count -gt 0)
                    {
                        Write-Verbose "Encountered $($errors.Count) parsing errors in $($file.Name)."
                    }

                    $functionAst = $ast.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

                    if ($functionAst)
                    {
                        $functionName = $functionAst.Name
                        $helpContent = $functionAst.GetHelpContent()

                        if ($helpContent)
                        {
                            # Extract synopsis, fallback to description
                            $synopsisText = if (-not [string]::IsNullOrWhiteSpace($helpContent.Synopsis))
                            {
                                $helpContent.Synopsis
                            }
                            elseif (-not [string]::IsNullOrWhiteSpace($helpContent.Description))
                            {
                                $helpContent.Description
                            }
                            else
                            {
                                'No description available'
                            }

                            # Normalize newlines and join multi-line text into a single line
                            $synopsis = ($synopsisText -split '\r?\n' | ForEach-Object { $_.Trim() }) -join ' '
                        }
                        else
                        {
                            $synopsis = 'No description available'
                        }
                    }
                    else
                    {
                        # Fallback for files that might not contain a standard function definition
                        $functionName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                        $synopsis = 'Could not parse function definition'
                    }

                    # Truncate if too long to keep single line
                    if ($synopsis.Length -gt 80)
                    {
                        $synopsis = $synopsis.Substring(0, 77) + '...'
                    }
                }
                catch
                {
                    Write-Verbose "Error parsing file $($file.Name): $($_.Exception.Message)"
                    $functionName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    $synopsis = 'Unable to read description'
                }

                # Format and display the function with description
                Write-Host ' - ' -ForegroundColor Yellow -NoNewline
                Write-Host $functionName -ForegroundColor Green -NoNewline
                Write-Host ' - ' -ForegroundColor Yellow -NoNewline
                Write-Host $synopsis -ForegroundColor White
            }

            # Write-Host "`nTotal functions: " -ForegroundColor Cyan -NoNewline
            # Write-Host $functionFiles.Count -ForegroundColor White

            # Add helpful footer
            Write-Host "`nFor full details about any function, use: " -ForegroundColor Gray -NoNewline
            Write-Host 'Get-Help <Function-Name>' -ForegroundColor White
            Write-Host 'Example: ' -ForegroundColor Gray -NoNewline
            Write-Host 'Get-Help Test-Port -Full' -ForegroundColor White
        }
        catch
        {
            Write-Error "Error processing Functions directory: $($_.Exception.Message)"
            throw $_
        }
    }

    end
    {
        Write-Verbose 'Show-ProfileFunctions completed'
    }
}
