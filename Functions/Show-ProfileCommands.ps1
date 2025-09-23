function Show-ProfileCommands
{
    <#
    .SYNOPSIS
        Shows a bulleted list of all available commands in the PowerShell profile Functions folder.

    .DESCRIPTION
        This function scans the Functions folder and extracts the SYNOPSIS from each PowerShell function file
        to display a simple bulleted list of available commands with their descriptions.
        Helps users discover what functions are available in their profile.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .EXAMPLE
        PS > Show-ProfileCommands

        - Get-CertificateDetails - Gets detailed information about a certificate
        - Get-CertificateExpiration - Checks certificate expiration dates
        - Test-DnsNameResolution - Tests if a DNS name can be resolved

        Displays all available profile commands with brief descriptions.

    .OUTPUTS
        System.String
        Formatted list of commands and descriptions
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    [OutputType([String])]
    param()

    begin
    {
        Write-Verbose 'Starting Show-ProfileCommands'

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
            # Get all PowerShell files in the Functions directory
            $functionFiles = Get-ChildItem -Path $functionsPath -Filter '*.ps1' -File | Sort-Object Name

            if (-not $functionFiles)
            {
                Write-Warning 'No PowerShell function files found in Functions directory'
                return
            }

            # Write-Host "`nAvailable Profile Commands:" -ForegroundColor Cyan
            # Write-Host ('=' * 50) -ForegroundColor Cyan
            Write-Host ''

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

                # Format and display the command with description
                Write-Host ' - ' -ForegroundColor Yellow -NoNewline
                Write-Host $functionName -ForegroundColor Green -NoNewline
                Write-Host ' - ' -ForegroundColor Yellow -NoNewline
                Write-Host $synopsis -ForegroundColor White
            }

            # Write-Host "`nTotal commands: " -ForegroundColor Cyan -NoNewline
            # Write-Host $functionFiles.Count -ForegroundColor White

            # Add helpful footer
            Write-Host "`nFor full details about any command, use: " -ForegroundColor Gray -NoNewline
            Write-Host 'Get-Help <Command-Name>' -ForegroundColor White
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
        Write-Verbose 'Show-ProfileCommands completed'
    }
}
