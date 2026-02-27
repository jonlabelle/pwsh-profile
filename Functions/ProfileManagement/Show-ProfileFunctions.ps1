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

    .PARAMETER Category
        Filter the output to show only functions from the specified category or categories.
        Accepts folder names (e.g., 'NetworkAndDns'), display names (e.g., 'Network And Dns'),
        or short aliases (e.g., 'dns', 'network'). Case-insensitive. Supports tab completion.

        Short aliases include: ad, dev, media, module, modules, network, net, dns, profile,
        sysadmin, sys, admin, utils, util.

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
        PS > Show-ProfileFunctions -Category network

        Network And Dns:
          - Get-DnsRecord - Retrieves DNS records for a specified domain name.
          - Test-Port - Tests network connectivity to a specified host and port.
        ...

        Displays only the Network And Dns category functions using the short alias 'network'.

    .EXAMPLE
        PS > Show-ProfileFunctions -Category dev, utils

        Developer:
          - Get-DotNetVersion - Gets the installed .NET Framework versions.
        ...

        Utilities:
          - Format-Bytes - Formats a number of bytes into a human-readable string.
        ...

        Displays functions from the Developer and Utilities categories.

    .OUTPUTS
        System.String
        Formatted list of functions and descriptions

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ProfileManagement/Show-ProfileFunctions.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ProfileManagement/Show-ProfileFunctions.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Position = 0)]
        [ArgumentCompleter({
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                $profileDir = if ($PROFILE) { Split-Path $PROFILE -Parent } else { $PSScriptRoot }
                $functionsDir = Join-Path -Path $profileDir -ChildPath 'Functions'
                if (-not (Test-Path $functionsDir)) { return }

                $folders = Get-ChildItem -Path $functionsDir -Directory | Select-Object -ExpandProperty Name

                # Custom short aliases for category names
                $shortcuts = @{
                    'ActiveDirectory' = @('ad')
                    'Developer' = @('dev')
                    'MediaProcessing' = @('media')
                    'ModuleManagement' = @('module', 'modules')
                    'NetworkAndDns' = @('network', 'dns', 'net')
                    'ProfileManagement' = @('profile')
                    'SystemAdministration' = @('sysadmin', 'sys', 'admin')
                    'Utilities' = @('utils', 'util')
                }

                $completions = [System.Collections.Generic.List[string]]::new()
                foreach ($folder in $folders)
                {
                    $completions.Add($folder)
                    $spaced = ($folder -creplace '([A-Z])', ' $1').Trim()
                    if ($spaced -ne $folder) { $completions.Add($spaced) }
                    if ($shortcuts.ContainsKey($folder))
                    {
                        foreach ($s in $shortcuts[$folder]) { $completions.Add($s) }
                    }
                }

                $completions | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object -Unique | ForEach-Object {
                    if ($_ -match '\s')
                    {
                        [System.Management.Automation.CompletionResult]::new("'$_'", $_, 'ParameterValue', $_)
                    }
                    else
                    {
                        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                    }
                }
            })]
        [string[]]$Category
    )

    begin
    {
        Write-Verbose 'Starting Show-ProfileFunctions'
        $skipProcessing = $false

        # Get the Functions directory path relative to the profile script
        $profilePath = $PROFILE
        if (-not $profilePath)
        {
            $profilePath = $PSCommandPath
        }

        $functionsPath = Join-Path -Path (Split-Path $profilePath -Parent) -ChildPath 'Functions'

        if (-not (Test-Path $functionsPath))
        {
            Write-Warning "Functions directory not found at: $functionsPath"
            $skipProcessing = $true
            return
        }

        Write-Verbose "Scanning Functions directory: $functionsPath"

        # Custom category shortcuts for friendly short names
        $categoryShortcuts = @{
            'ActiveDirectory' = @('ad')
            'Developer' = @('dev')
            'MediaProcessing' = @('media')
            'ModuleManagement' = @('module', 'modules')
            'NetworkAndDns' = @('network', 'dns', 'net')
            'ProfileManagement' = @('profile')
            'SystemAdministration' = @('sysadmin', 'sys', 'admin')
            'Utilities' = @('utils', 'util')
        }

        # Resolve user-specified category names to actual folder names
        $resolvedCategories = @()
        if ($Category)
        {
            $allFolders = Get-ChildItem -Path $functionsPath -Directory | Select-Object -ExpandProperty Name

            foreach ($cat in $Category)
            {
                $catLower = $cat.ToLower()
                $matched = $null

                # Check custom shortcuts
                foreach ($folder in $categoryShortcuts.Keys)
                {
                    if ($categoryShortcuts[$folder] -contains $catLower)
                    {
                        $matched = $folder
                        break
                    }
                }

                # Check exact folder name (case-insensitive)
                if (-not $matched)
                {
                    $matched = $allFolders | Where-Object { $_.ToLower() -eq $catLower } | Select-Object -First 1
                }

                # Check spaced version (e.g., "Network And Dns" matches "NetworkAndDns")
                if (-not $matched)
                {
                    $matched = $allFolders | Where-Object {
                        $spaced = ($_ -creplace '([A-Z])', ' $1').Trim()
                        $spaced.ToLower() -eq $catLower
                    } | Select-Object -First 1
                }

                if ($matched)
                {
                    $resolvedCategories += $matched
                    Write-Verbose "Resolved category '$cat' to folder '$matched'"
                }
                else
                {
                    Write-Warning "Unknown category: '$cat'. Use tab completion to see available categories."
                }
            }

            if ($resolvedCategories.Count -eq 0)
            {
                Write-Warning 'No valid categories specified. Run without -Category to see all.'
                $skipProcessing = $true
                return
            }
        }
    }

    process
    {
        if ($skipProcessing) { return }

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

            # Filter by specified categories if provided
            if ($resolvedCategories.Count -gt 0)
            {
                $functionsByCategory = $functionsByCategory | Where-Object { $resolvedCategories -contains $_.Name }
            }

            if (-not $functionsByCategory)
            {
                Write-Warning 'No functions found for the specified categories.'
                return
            }

            $firstCategory = $true

            foreach ($categoryGroup in $functionsByCategory)
            {
                # Add spaces to category name (e.g., "NetworkAndDns" -> "Network And Dns")
                $categoryDisplay = $categoryGroup.Name -creplace '([A-Z])', ' $1'
                $categoryDisplay = $categoryDisplay.Trim()

                # Display category header with blank line before (except first)
                if ($firstCategory)
                {
                    Write-Host "`n${categoryDisplay}:" -ForegroundColor Cyan
                    $firstCategory = $false
                }
                else
                {
                    Write-Host "`n${categoryDisplay}:" -ForegroundColor Cyan
                }

                # Sort functions within category
                $sortedFiles = $categoryGroup.Group | Sort-Object Name

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

                            # Fallback: If GetHelpContent() returns null or empty, manually parse the help block
                            if (-not $helpContent -or [string]::IsNullOrWhiteSpace($helpContent.Synopsis))
                            {
                                Write-Verbose "GetHelpContent() failed for $($file.Name), using manual parsing"
                                $fileContent = Get-Content $file.FullName -Raw

                                # Extract .SYNOPSIS using regex - handle multi-line content
                                if ($fileContent -match '(?s)\.SYNOPSIS\s+(.+?)(?=\r?\n\s*\.)')
                                {
                                    $synopsisText = $matches[1].Trim()

                                    # Create a minimal help content object
                                    $helpContent = [PSCustomObject]@{
                                        Synopsis = $synopsisText
                                        Description = $null
                                    }
                                }
                            }

                            # Extract aliases from Set-Alias commands in the file
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

                    # Display aliases if available
                    if ($aliases.Count -gt 0)
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
            $displayedCount = ($functionsByCategory | ForEach-Object { $_.Group.Count } | Measure-Object -Sum).Sum
            $categoryCount = @($functionsByCategory).Count
            Write-Host "`nTotal: " -ForegroundColor Cyan -NoNewline
            Write-Host "$displayedCount functions " -ForegroundColor White -NoNewline
            Write-Host 'across ' -ForegroundColor Cyan -NoNewline
            Write-Host "$categoryCount categories" -ForegroundColor White

            Write-Host "`nAliases shown in parentheses are only created if they don't already exist in the environment." -ForegroundColor DarkGray

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
