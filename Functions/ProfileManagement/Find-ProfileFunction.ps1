function Find-ProfileFunction
{
    <#
    .SYNOPSIS
        Searches profile functions to help find the right command quickly.

    .DESCRIPTION
        Scans the profile `Functions` directory, extracts metadata from each function file,
        and returns ranked matches based on keyword relevance.

        Search matching considers:
        - Function name
        - Function synopsis (from comment-based help)
        - Category/folder name
        - Aliases defined with Set-Alias in the function file

        Compatible with PowerShell Desktop 5.1+ on Windows, macOS, and Linux.

    .PARAMETER Query
        One or more search terms. Terms are split on whitespace.
        By default, all terms must match each result. Use -MatchAny to match any term.

    .PARAMETER Category
        Optional category filter. Accepts folder names (e.g., 'NetworkAndDns'),
        display names (e.g., 'Network And Dns'), or short aliases (e.g., 'dns', 'dev').
        Case-insensitive. Supports tab completion.

        Short aliases include: ad, dev, media, module, modules, network, net, dns, profile,
        sysadmin, sys, admin, utils, util.

    .PARAMETER Top
        Maximum number of ranked results to return.

    .PARAMETER MatchAny
        Match results containing any query term. By default, all query terms are required.

    .EXAMPLE
        PS > Find-ProfileFunction dns

        Finds functions related to DNS and returns ranked matches.

    .EXAMPLE
        PS > Find-ProfileFunction 'markdown convert'

        Name     : ConvertTo-Markdown
        Category : Utilities
        Synopsis : Converts a URL or local file path to Markdown using Pandoc.
        Aliases  : url2markdown
        Score    : 285
        Path     : /Users/jon/.config/powershell/Functions/Utilities/ConvertTo-Markdown.ps1

        Name     : ConvertTo-MarkdownObject
        Category : Utilities
        Synopsis : Converts arbitrary PowerShell objects into Markdown text.
        Aliases  :
        Score    : 235
        Path     : /Users/jon/.config/powershell/Functions/Utilities/ConvertTo-MarkdownObject.ps1

        Finds functions that match both "markdown" and "convert".

    .EXAMPLE
        PS > Find-ProfileFunction docker -Category dev -Top 5

        Returns the top 5 Docker-related functions in the Developer category.

    .EXAMPLE
        PS > Find-ProfileFunction reboot | Format-Table Name, Category, Synopsis -AutoSize

        Pipes ranked results into a custom table layout.

    .OUTPUTS
        PSCustomObject
        Returns objects with properties:
        Name, Category, Synopsis, Aliases, Score, Path

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ProfileManagement/Find-ProfileFunction.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/ProfileManagement/Find-ProfileFunction.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Query,

        [Parameter()]
        [ArgumentCompleter({
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                $profileDir = if ($PROFILE) { Split-Path $PROFILE -Parent } else { $PSScriptRoot }
                $functionsDir = Join-Path -Path $profileDir -ChildPath 'Functions'
                if (-not (Test-Path $functionsDir)) { return }

                $folders = Get-ChildItem -Path $functionsDir -Directory | Select-Object -ExpandProperty Name

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
                        foreach ($shortcut in $shortcuts[$folder])
                        {
                            $completions.Add($shortcut)
                        }
                    }
                }

                $completions |
                Where-Object { $_ -like "$wordToComplete*" } |
                Sort-Object -Unique |
                ForEach-Object {
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
        [string[]]$Category,

        [Parameter()]
        [ValidateRange(1, 500)]
        [int]$Top = 15,

        [Parameter()]
        [switch]$MatchAny
    )

    begin
    {
        Write-Verbose 'Starting Find-ProfileFunction'

        $skipProcessing = $false
        $resolvedCategories = @()
        $searchTerms = @()
        $queryPhrase = ''

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

        $profilePath = $PROFILE
        if (-not $profilePath)
        {
            $profilePath = $PSCommandPath
        }

        $functionsPath = Join-Path -Path (Split-Path -Path $profilePath -Parent) -ChildPath 'Functions'

        if (-not (Test-Path -LiteralPath $functionsPath -PathType Container))
        {
            Write-Warning "Functions directory not found at: $functionsPath"
            $skipProcessing = $true
            return
        }

        foreach ($item in $Query)
        {
            if ([string]::IsNullOrWhiteSpace($item))
            {
                continue
            }

            foreach ($term in ($item -split '\s+'))
            {
                if (-not [string]::IsNullOrWhiteSpace($term))
                {
                    $searchTerms += $term.ToLowerInvariant()
                }
            }
        }

        if ($searchTerms.Count -eq 0)
        {
            Write-Warning 'At least one non-empty search term is required.'
            $skipProcessing = $true
            return
        }

        $queryPhrase = (($Query -join ' ').Trim()).ToLowerInvariant()

        if ($Category)
        {
            $allFolders = Get-ChildItem -Path $functionsPath -Directory | Select-Object -ExpandProperty Name

            foreach ($cat in $Category)
            {
                $catLower = $cat.ToLowerInvariant()
                $matched = $null

                foreach ($folder in $categoryShortcuts.Keys)
                {
                    if ($categoryShortcuts[$folder] -contains $catLower)
                    {
                        $matched = $folder
                        break
                    }
                }

                if (-not $matched)
                {
                    $matched = $allFolders | Where-Object { $_.ToLowerInvariant() -eq $catLower } | Select-Object -First 1
                }

                if (-not $matched)
                {
                    $matched = $allFolders |
                    Where-Object {
                        (($_ -creplace '([A-Z])', ' $1').Trim()).ToLowerInvariant() -eq $catLower
                    } |
                    Select-Object -First 1
                }

                if ($matched)
                {
                    $resolvedCategories += $matched
                    Write-Verbose "Resolved category '$cat' to '$matched'"
                }
                else
                {
                    Write-Warning "Unknown category: '$cat'. Use tab completion to see available categories."
                }
            }

            $resolvedCategories = $resolvedCategories | Sort-Object -Unique

            if ($resolvedCategories.Count -eq 0)
            {
                Write-Warning 'No valid categories specified. Run without -Category to search all.'
                $skipProcessing = $true
                return
            }
        }
    }

    process
    {
        if ($skipProcessing) { return }

        function Get-FunctionSynopsis
        {
            param(
                [Parameter(Mandatory)]
                [string]$Path,

                [Parameter(Mandatory)]
                [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst
            )

            $helpContent = $FunctionAst.GetHelpContent()
            if ($helpContent -and -not [string]::IsNullOrWhiteSpace($helpContent.Synopsis))
            {
                return (($helpContent.Synopsis -split '\r?\n' | ForEach-Object { $_.Trim() }) -join ' ')
            }

            $raw = Get-Content -LiteralPath $Path -Raw
            if ($raw -match '(?s)\.SYNOPSIS\s+(.+?)(?=\r?\n\s*\.)')
            {
                return (($matches[1].Trim() -split '\r?\n' | ForEach-Object { $_.Trim() }) -join ' ')
            }

            return 'No description available'
        }

        function Get-FunctionAliases
        {
            param(
                [Parameter(Mandatory)]
                [System.Management.Automation.Language.ScriptBlockAst]$Ast
            )

            $foundAliases = [System.Collections.Generic.List[string]]::new()

            $setAliasCalls = $Ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                    $args[0].GetCommandName() -eq 'Set-Alias'
                }, $true)

            foreach ($aliasCall in $setAliasCalls)
            {
                $aliasName = $null

                $nameParam = $aliasCall.CommandElements | Where-Object {
                    $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $_.ParameterName -eq 'Name'
                } | Select-Object -First 1

                if ($nameParam)
                {
                    $nameIndex = $aliasCall.CommandElements.IndexOf($nameParam)
                    if ($nameIndex -ge 0 -and ($nameIndex + 1) -lt $aliasCall.CommandElements.Count)
                    {
                        $nameElement = $aliasCall.CommandElements[$nameIndex + 1]
                        if ($nameElement -is [System.Management.Automation.Language.StringConstantExpressionAst])
                        {
                            $aliasName = $nameElement.Value
                        }
                    }
                }

                if (-not $aliasName -and $aliasCall.CommandElements.Count -ge 2)
                {
                    $possibleAlias = $aliasCall.CommandElements[1]
                    if ($possibleAlias -is [System.Management.Automation.Language.StringConstantExpressionAst])
                    {
                        $aliasName = $possibleAlias.Value
                    }
                }

                if (-not [string]::IsNullOrWhiteSpace($aliasName) -and -not $foundAliases.Contains($aliasName))
                {
                    [void]$foundAliases.Add($aliasName)
                }
            }

            return @($foundAliases)
        }

        function Get-Score
        {
            param(
                [Parameter(Mandatory)]
                [PSCustomObject]$Metadata,

                [Parameter(Mandatory)]
                [string[]]$Terms,

                [Parameter(Mandatory)]
                [bool]$UseMatchAny,

                [Parameter(Mandatory)]
                [string]$QueryText
            )

            $score = 0
            $matchedTerms = 0

            foreach ($term in $Terms)
            {
                $termMatched = $false

                if ($Metadata.NameLower -eq $term)
                {
                    $score += 120
                    $termMatched = $true
                }
                elseif ($Metadata.NameLower.StartsWith($term))
                {
                    $score += 95
                    $termMatched = $true
                }
                elseif ($Metadata.NameLower.Contains($term))
                {
                    $score += 70
                    $termMatched = $true
                }

                if ($Metadata.AliasesLower -contains $term)
                {
                    $score += 80
                    $termMatched = $true
                }
                elseif ($Metadata.AliasesLower | Where-Object { $_ -like "*$term*" })
                {
                    $score += 50
                    $termMatched = $true
                }

                if ($Metadata.SynopsisLower.Contains($term))
                {
                    $score += 35
                    $termMatched = $true
                }

                if ($Metadata.CategoryLower -eq $term -or $Metadata.CategoryDisplayLower -eq $term)
                {
                    $score += 40
                    $termMatched = $true
                }
                elseif ($Metadata.CategoryLower.Contains($term) -or $Metadata.CategoryDisplayLower.Contains($term))
                {
                    $score += 20
                    $termMatched = $true
                }

                if ($termMatched)
                {
                    $matchedTerms++
                }
            }

            if ($matchedTerms -eq 0)
            {
                return -1
            }

            if (-not $UseMatchAny -and $matchedTerms -lt $Terms.Count)
            {
                return -1
            }

            if (-not [string]::IsNullOrWhiteSpace($QueryText))
            {
                if ($Metadata.NameLower.Contains($QueryText))
                {
                    $score += 40
                }

                if ($Metadata.SynopsisLower.Contains($QueryText))
                {
                    $score += 20
                }
            }

            return $score
        }

        try
        {
            $functionFiles = Get-ChildItem -Path $functionsPath -Filter '*.ps1' -File -Recurse

            if ($resolvedCategories.Count -gt 0)
            {
                $functionFiles = $functionFiles | Where-Object { $resolvedCategories -contains $_.Directory.Name }
            }

            if (-not $functionFiles)
            {
                Write-Warning 'No function files found for the specified filter.'
                return
            }

            $results = [System.Collections.Generic.List[object]]::new()

            foreach ($file in $functionFiles)
            {
                try
                {
                    $tokens = $null
                    $errors = $null
                    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)

                    $functionAst = $ast.Find({
                            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
                        }, $true)

                    $functionName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                    if ($functionAst)
                    {
                        $functionName = $functionAst.Name
                    }

                    $synopsis = if ($functionAst)
                    {
                        Get-FunctionSynopsis -Path $file.FullName -FunctionAst $functionAst
                    }
                    else
                    {
                        'Could not parse function definition'
                    }

                    $aliases = if ($ast)
                    {
                        Get-FunctionAliases -Ast $ast
                    }
                    else
                    {
                        @()
                    }

                    $category = $file.Directory.Name
                    $categoryDisplay = ($category -creplace '([A-Z])', ' $1').Trim()

                    $metadata = [PSCustomObject]@{
                        Name = $functionName
                        NameLower = $functionName.ToLowerInvariant()
                        Category = $category
                        CategoryLower = $category.ToLowerInvariant()
                        CategoryDisplay = $categoryDisplay
                        CategoryDisplayLower = $categoryDisplay.ToLowerInvariant()
                        Synopsis = $synopsis
                        SynopsisLower = $synopsis.ToLowerInvariant()
                        Aliases = @($aliases)
                        AliasesLower = @($aliases | ForEach-Object { $_.ToLowerInvariant() })
                        Path = $file.FullName
                    }

                    $score = Get-Score -Metadata $metadata -Terms $searchTerms -UseMatchAny $MatchAny.IsPresent -QueryText $queryPhrase

                    if ($score -ge 0)
                    {
                        $results.Add([PSCustomObject]@{
                                Name = $metadata.Name
                                Category = $metadata.CategoryDisplay
                                Synopsis = $metadata.Synopsis
                                Aliases = ($metadata.Aliases -join ', ')
                                Score = $score
                                Path = $metadata.Path
                            })
                    }
                }
                catch
                {
                    Write-Verbose "Skipping $($file.FullName): $($_.Exception.Message)"
                }
            }

            if ($results.Count -eq 0)
            {
                Write-Warning "No functions matched query: '$($Query -join ' ')'"
                return
            }

            $rankedResults = $results |
            Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Name'; Descending = $false } |
            Select-Object -First $Top

            $rankedResults
        }
        catch
        {
            Write-Error "Error searching profile functions: $($_.Exception.Message)"
            throw
        }
    }

    end
    {
        Write-Verbose 'Find-ProfileFunction completed'
    }
}

# Create alias 'Search-ProfileFunction' if it doesn't conflict
if (-not (Get-Command -Name 'Search-ProfileFunction' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'Search-ProfileFunction' alias for Find-ProfileFunction"
        Set-Alias -Name 'Search-ProfileFunction' -Value 'Find-ProfileFunction' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Find-ProfileFunction: Could not create 'Search-ProfileFunction' alias: $($_.Exception.Message)"
    }
}
