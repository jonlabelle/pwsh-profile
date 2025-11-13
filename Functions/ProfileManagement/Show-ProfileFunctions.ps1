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
                $functionName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $synopsis = ''

                try
                {
                    # Read the file content to extract SYNOPSIS
                    $content = Get-Content $file.FullName -Raw -ErrorAction Stop

                    # Use regex to find the SYNOPSIS or DESCRIPTION section
                    if ($content -match '\.SYNOPSIS\s*\r?\n\s*(.+?)(?:\r?\n\s*\r?\n|\r?\n\s*\.)')
                    {
                        $synopsis = $matches[1].Trim()
                        # Remove any leading/trailing whitespace and normalize line breaks
                        $synopsis = $synopsis -replace '\r?\n\s*', ' ' -replace '\s+', ' '
                    }
                    elseif ($content -match '\.SYNOPSIS\s*\r?\n\s*(.+?)(?:\r?\n|\.)')
                    {
                        $synopsis = $matches[1].Trim()
                        $synopsis = $synopsis -replace '\r?\n\s*', ' ' -replace '\s+', ' '
                    }
                    elseif ($content -match '\.DESCRIPTION\s*\r?\n\s*(.+?)(?:\r?\n\s*\r?\n|\r?\n\s*\.)')
                    {
                        $synopsis = $matches[1].Trim()
                        $synopsis = $synopsis -replace '\r?\n\s*', ' ' -replace '\s+', ' '
                    }
                    else
                    {
                        $synopsis = 'No description available'
                    }

                    # Truncate if too long to keep single line
                    if ($synopsis.Length -gt 80)
                    {
                        $synopsis = $synopsis.Substring(0, 77) + '...'
                    }
                }
                catch
                {
                    Write-Verbose "Error reading file $($file.Name): $($_.Exception.Message)"
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
