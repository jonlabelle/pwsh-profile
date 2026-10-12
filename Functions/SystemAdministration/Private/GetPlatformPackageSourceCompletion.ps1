function Get-PlatformPackageSourceCompletion
{
    param(
        [Parameter()]
        [String]$WordToComplete = '',

        [Parameter()]
        [System.Collections.IDictionary]$BoundParameters = @{}
    )

    # A directly supplied package list is the most accurate source of export suggestions.
    if ($BoundParameters.Contains('Package'))
    {
        $sources = @($BoundParameters['Package'] | Where-Object { $null -ne $_ } | ForEach-Object { "$($_.Source)".Trim() })
    }
    else
    {
        try
        {
            if (-not (Get-Command -Name Get-PlatformPackage -ErrorAction SilentlyContinue))
            {
                . (Join-Path -Path $PSScriptRoot -ChildPath '../Get-PlatformPackage.ps1')
            }

            $query = [Ordered]@{ SkipDescriptionEnrichment = $true; ErrorAction = 'Stop'; WarningAction = 'SilentlyContinue' }
            foreach ($parameterName in @('PackageManager', 'Name', 'ExcludePackage', 'ExplicitOnly'))
            {
                if ($BoundParameters.Contains($parameterName))
                {
                    $query[$parameterName] = $BoundParameters[$parameterName]
                }
            }

            $cacheKey = $query | ConvertTo-Json -Compress
            if ($null -eq $script:PlatformPackageSourceCompletionCache)
            {
                $script:PlatformPackageSourceCompletionCache = @{}
            }
            foreach ($key in @($script:PlatformPackageSourceCompletionCache.Keys))
            {
                if ($script:PlatformPackageSourceCompletionCache[$key].ExpiresAt -le [DateTime]::UtcNow)
                {
                    $script:PlatformPackageSourceCompletionCache.Remove($key)
                }
            }

            $cached = $script:PlatformPackageSourceCompletionCache[$cacheKey]
            if ($null -ne $cached)
            {
                $sources = @($cached.Sources)
            }
            else
            {
                $sources = @(Get-PlatformPackage @query | ForEach-Object { "$($_.Source)".Trim() })
                $script:PlatformPackageSourceCompletionCache[$cacheKey] = [PSCustomObject]@{
                    ExpiresAt = [DateTime]::UtcNow.AddMinutes(1)
                    Sources = $sources
                }
            }
        }
        catch
        {
            # Completion should not interrupt typing when the package manager is unavailable.
            return
        }
    }

    $prefix = $WordToComplete.TrimStart("'", '"')
    @($sources | Where-Object { -not [String]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique) |
    Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } |
    ForEach-Object {
        $quoted = "'" + $_.Replace("'", "''") + "'"
        [System.Management.Automation.CompletionResult]::new($quoted, $_, 'ParameterValue', $_)
    }
}
