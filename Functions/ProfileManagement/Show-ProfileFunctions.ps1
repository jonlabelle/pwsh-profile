function Show-ProfileFunctions
{
    <#
    .SYNOPSIS
        Shows a bulleted list of all available functions in the PowerShell profile Functions folder.

    .DESCRIPTION
        This function scans the Functions folder and extracts the SYNOPSIS from each PowerShell function file
        to display a categorized list of available functions with their descriptions.
        Functions are grouped by their category folder and sorted alphabetically within each category.
        Helps users discover what functions are available in their profile.

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER IncludeAliases
        Include function aliases in the output. Shows aliases that are conditionally created
        when the function is loaded (only if the alias name doesn't already exist).

    .EXAMPLE
        PS > Show-ProfileFunctions

        Active Directory Functions:
          - Invoke-GroupPolicyUpdate - Forces an immediate Group Policy update on Windows systems.
          - Test-ADCredential - Test the username and password of Active Directory credentials.
          - Test-ADUserLocked - Test if an Active Directory user account is locked out.

        Developer Functions:
          - Get-DotNetVersion - Gets the installed .NET Framework versions.
          - Import-DotEnv - Loads environment variables from dotenv (.env) files.
          - Remove-DotNetBuildArtifacts - Removes bin and obj folders from .NET project directories.
        ...

        Total: 52 functions across 7 categories

        Displays all available profile functions organized by category with brief descriptions.

    .EXAMPLE
        PS > Show-ProfileFunctions -IncludeAliases

        Developer Functions:
          - Import-DotEnv (dotenv*) - Loads environment variables from dotenv (.env) files.

        Utilities Functions:
          - ConvertFrom-Base64 (base64-decode*) - Decodes a Base64-encoded string...
          - ConvertTo-Base64 (base64-encode*) - Converts a string or file content to Base64...
          - Get-WhichCommand (which*) - Locates a command and displays its location...
        ...

        * Aliases are only created if they don't already exist in the environment

        Displays functions with their conditionally-created aliases.

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
    param(
        [Parameter()]
        [switch]$IncludeAliases
    )

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
            $functionFiles = Get-ChildItem -Path $functionsPath -Filter '*.ps1' -File -Recurse

            if (-not $functionFiles)
            {
                Write-Warning 'No PowerShell function files found in Functions directory'
                return
            }

            # Group functions by category (parent folder)
            $functionsByCategory = $functionFiles | Group-Object { $_.Directory.Name } | Sort-Object Name

            $firstCategory = $true

            foreach ($category in $functionsByCategory)
            {
                # Add spaces to category name (e.g., "NetworkAndDns" -> "Network And Dns")
                $categoryDisplay = $category.Name -creplace '([A-Z])', ' $1'
                $categoryDisplay = $categoryDisplay.Trim()

                # Display category header with blank line before (except first)
                if ($firstCategory)
                {
                    Write-Host "`n$categoryDisplay Functions:" -ForegroundColor Cyan
                    $firstCategory = $false
                }
                else
                {
                    Write-Host "`n$categoryDisplay Functions:" -ForegroundColor Cyan
                }

                # Sort functions within category
                $sortedFiles = $category.Group | Sort-Object Name

                foreach ($file in $sortedFiles)
                {
                    $functionName = ''
                    $synopsis = ''
                    $aliases = @()

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

                            # Extract aliases if requested
                            if ($IncludeAliases)
                            {
                                # Find Set-Alias commands in the file
                                $setAliasCalls = $ast.FindAll({
                                        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                                        $args[0].GetCommandName() -eq 'Set-Alias'
                                    }, $true)

                                foreach ($aliasCall in $setAliasCalls)
                                {
                                    # Extract the -Name parameter value
                                    $nameParam = $aliasCall.CommandElements | Where-Object {
                                        $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                                        $_.ParameterName -eq 'Name'
                                    }

                                    if ($nameParam)
                                    {
                                        $nameIndex = $aliasCall.CommandElements.IndexOf($nameParam)
                                        if ($nameIndex -ge 0 -and ($nameIndex + 1) -lt $aliasCall.CommandElements.Count)
                                        {
                                            $aliasValue = $aliasCall.CommandElements[$nameIndex + 1]
                                            if ($aliasValue -is [System.Management.Automation.Language.StringConstantExpressionAst])
                                            {
                                                $aliases += $aliasValue.Value
                                            }
                                        }
                                    }
                                }
                            }

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
                    Write-Host '  - ' -ForegroundColor Yellow -NoNewline
                    Write-Host $functionName -ForegroundColor Green -NoNewline

                    # Display aliases if requested and available
                    if ($IncludeAliases -and $aliases.Count -gt 0)
                    {
                        Write-Host ' (' -ForegroundColor Gray -NoNewline
                        Write-Host ($aliases -join ', ') -ForegroundColor DarkGray -NoNewline
                        # Write-Host '*' -ForegroundColor Gray -NoNewline
                        Write-Host ')' -ForegroundColor Gray -NoNewline
                    }

                    Write-Host ' - ' -ForegroundColor Yellow -NoNewline
                    Write-Host $synopsis -ForegroundColor White
                }
            }

            # Display summary statistics
            Write-Host "`nTotal: " -ForegroundColor Cyan -NoNewline
            Write-Host "$($functionFiles.Count) functions " -ForegroundColor White -NoNewline
            Write-Host 'across ' -ForegroundColor Cyan -NoNewline
            Write-Host "$($functionsByCategory.Count) categories" -ForegroundColor White

            # Add alias note if included, or hint if not
            if ($IncludeAliases)
            {
                Write-Host "`n* Aliases are only created if they don't already exist in the environment" -ForegroundColor DarkGray
            }
            else
            {
                Write-Host "`nTip: Use " -ForegroundColor Gray -NoNewline
                Write-Host 'Show-ProfileFunctions -IncludeAliases' -ForegroundColor Cyan -NoNewline
                Write-Host ' to see function aliases' -ForegroundColor Gray
            }

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
