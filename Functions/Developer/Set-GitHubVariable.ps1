function Set-GitHubVariable
{
    <#
    .SYNOPSIS
        Creates or updates a GitHub configuration variable at an explicit repository, environment, or organization scope.

    .DESCRIPTION
        Creates or updates a GitHub configuration variable. Scope selection is always explicit through
        the required -Scope parameter.

        Repository scope can omit -Repository and use the current Git repository's origin remote.
        Environment and organization scopes require their matching target parameters.

        The function prefers the GitHub CLI-backed API transport when `gh` is available and falls
        back to direct REST API requests otherwise. Existing variables are updated only when -Force
        is used, unless the current value already matches the requested value.

        The function supports:
        - Repository, environment, and organization variables via -Scope
        - Organization visibility and selected repository targeting
        - -WhatIf/-Confirm through ShouldProcess
        - Secure PAT input via -Token with fallback to GH_TOKEN
        - Exponential backoff retries for transient failures

    .PARAMETER Name
        The GitHub variable name.

        Configuration variable names:
        - Can contain only letters, numbers, and underscores
        - Cannot start with a number
        - Cannot start with the GITHUB_ prefix
        - Are case-insensitive when referenced by GitHub

    .PARAMETER Value
        The variable value to store.

        Variables are stored as plain text rather than as encrypted secrets, so use
        Set-GitHubSecret for sensitive values.

        GitHub configuration variables are intended for non-secret configuration that GitHub Actions
        workflows can reference with `${{ vars.NAME }}`. At repository and organization scope,
        GitHub also makes variables available to Dependabot where GitHub supports that behavior.

        Empty string values are allowed.

    .PARAMETER Scope
        The GitHub variable scope. Valid values are Repository, Environment, and Organization.

        Meanings:
        - Repository: a repository-level variable for one repository
        - Environment: an environment-level variable for one deployment environment in a repository
        - Organization: an organization-level variable that can be shared with repositories

        Companion parameter rules:
        - Repository: use -Scope Repository; -Repository is optional
        - Environment: use -Scope Environment; -Repository and -Environment are required
        - Organization: use -Scope Organization; -Organization is required

    .PARAMETER Repository
        The target repository in OWNER/REPO or HOST/OWNER/REPO format.

        Supported with -Scope Repository and -Scope Environment.

        Repository variables are available within the specified repository. Environment variables
        belong to a specific environment in the specified repository.

        When -Scope Repository is used and -Repository is omitted, the function tries to resolve the
        current Git repository's origin remote. If that cannot be determined, specify -Repository
        explicitly.

        Examples:
        - octo-org/service-api
        - github.example.com/platform/service-api

    .PARAMETER Environment
        The deployment environment name for environment variables.

        Supported only with -Scope Environment and requires -Repository.

        Environment variables belong to a single named environment within the repository and are
        intended for jobs that reference that environment.

        GitHub environment names:
        - Are not case sensitive
        - May not exceed 255 characters
        - Must be unique within the repository

        GitHub REST endpoints require environment names to be URL-encoded. This function handles
        that automatically, so names containing spaces or `/` are supported.

    .PARAMETER Organization
        The target organization for organization variables.

        Supported only with -Scope Organization.

        Organization variables can be shared with repositories in the organization according to the
        access policy set by -Visibility and -SelectedRepository.

    .PARAMETER Visibility
        Organization variable visibility. Valid values are all, private, and selected.

        Supported only with -Scope Organization.

        Meanings:
        - all: every repository in the organization can use the variable
        - private: only private repositories in the organization can use the variable
        - selected: only repositories listed in -SelectedRepository can use the variable

        When -SelectedRepository is used and -Visibility is omitted, visibility is treated as
        selected. When a new organization variable is created without any explicit access settings,
        the function uses GitHub's default private visibility.

        When you update an existing organization variable without -Visibility or
        -SelectedRepository, the function preserves the variable's current access policy.

    .PARAMETER SelectedRepository
        The repositories that can access an organization variable.

        Supported only with -Scope Organization.

        This is the repository allow-list used when an organization variable has selected visibility.
        If you provide -SelectedRepository and omit -Visibility, the function treats the access
        policy as selected.

        Bare repository names such as 'app1' are resolved relative to -Organization for REST API
        fallback. OWNER/REPO format also works.

    .PARAMETER Force
        Overwrites an existing variable when the current value differs.

        If the existing value already matches the requested value, the function returns Unchanged
        and does not require -Force.

        Result behavior:
        - Existing variable + same value: Unchanged
        - Existing variable + different value + no -Force: Skipped
        - Existing variable + different value + -Force: Updated
        - Missing variable: Created

    .PARAMETER Token
        Optional GitHub personal access token as a SecureString.

        If supplied, the token is used only for the outbound `gh` or REST request and is never
        written to command output.

        When omitted, the function checks the environment variable named by
        -TokenEnvironmentVariableName. If the GitHub CLI is installed, its existing authenticated
        session can also be used when no token is supplied. If `gh` is not available and the
        function falls back to REST, a token or token environment variable is required.

    .PARAMETER TokenEnvironmentVariableName
        The environment variable name to check for a GitHub token when -Token is not supplied.

        Defaults to GH_TOKEN.

        This environment variable is read only when -Token is not supplied. It is used for `gh`
        authentication and REST fallback.

    .EXAMPLE
        PS > Set-GitHubVariable -Name 'DOTNET_VERSION' -Value '8.0.x' -Scope Repository

        Creates a repository variable for the current Git repository.

    .EXAMPLE
        PS > Set-GitHubVariable -Name 'DEPLOY_RING' -Value 'production' -Scope Environment -Repository 'octo-org/service-api' -Environment 'Production'

        Creates an environment variable for the Production deployment environment.

    .EXAMPLE
        PS > Set-GitHubVariable -Name 'REGION' -Value 'us-east-1' -Scope Organization -Organization 'octo-org' -Visibility selected -SelectedRepository 'app1', 'app2'

        Creates an organization variable that is visible only to selected repositories.

    .EXAMPLE
        PS > Set-GitHubVariable -Name 'FEATURE_FLAG' -Value 'enabled' -Scope Organization -Organization 'octo-org'

        Creates an organization variable that defaults to GitHub's private visibility.

    .EXAMPLE
        PS > Set-GitHubVariable -Name 'FEATURE_FLAG' -Value 'enabled' -Scope Organization -Organization 'octo-org' -Force

        Overwrites an existing organization variable.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > Set-GitHubVariable -Name 'BUILD_CONFIGURATION' -Value 'Release' -Scope Repository -Repository 'octo-org/service-api' -Token $token -WhatIf

        Shows what would happen without modifying the variable.

    .EXAMPLE
        PS > Set-GitHubVariable -Name 'PACKAGE_SOURCE' -Value 'internal' -Scope Organization -Organization 'octo-org' -TokenEnvironmentVariableName 'GITHUB_ADMIN_TOKEN'

        Reads the GitHub token from a non-default environment variable.

    .OUTPUTS
        GitHub.VariableSetResult

        Returns a summary object with status, target scope, transport used, and whether the variable
        changed.

    .NOTES
        -Scope is required for all GitHub helper functions in this module family.
        Variables prefer the GitHub CLI-backed transport and fall back to direct REST API requests.
        Organization variables default to private visibility when they are created without explicit
        visibility settings.

    .LINK
        https://cli.github.com/manual/gh_variable_set

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Set-GitHubVariable.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if ($_ -match '^(?i:GITHUB_)')
                {
                    throw "GitHub variable names cannot start with the 'GITHUB_' prefix."
                }

                if ($_ -notmatch '^(?![0-9])[A-Za-z0-9_]+$')
                {
                    throw 'GitHub variable names may only contain letters, numbers, or underscores, and cannot start with a number.'
                }

                $true
            })]
        [String]$Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [String]$Value,

        [Parameter(Mandatory)]
        [ValidateSet('Repository', 'Environment', 'Organization')]
        [String]$Scope,

        [Parameter()]
        [String]$Repository,

        [Parameter()]
        [ValidateScript({
                if ([string]::IsNullOrWhiteSpace($_))
                {
                    throw 'GitHub environment names cannot be empty or whitespace.'
                }

                if ($_.Length -gt 255)
                {
                    throw 'GitHub environment names may not exceed 255 characters.'
                }

                $true
            })]
        [String]$Environment,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$Organization,

        [Parameter()]
        [ValidateSet('all', 'private', 'selected')]
        [String]$Visibility,

        [Parameter()]
        [String[]]$SelectedRepository,

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [SecureString]$Token,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TokenEnvironmentVariableName = 'GH_TOKEN'

    )

    begin
    {
        function Import-GitHubConfigurationHelpersIfNeeded
        {
            if (-not (Get-Variable -Name 'PwshProfileGitHubConfigurationHelpers' -Scope Script -ErrorAction SilentlyContinue))
            {
                $dependencyDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
                $dependencyPath = Join-Path -Path $dependencyDirectory -ChildPath 'GitHubConfigurationHelpers.ps1'
                $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

                if (-not (Test-Path -LiteralPath $dependencyPath -PathType Leaf))
                {
                    throw "Required dependency could not be found. Expected location: $dependencyPath"
                }

                try
                {
                    . $dependencyPath
                    Write-Verbose "Loaded GitHub configuration helpers from: $dependencyPath"
                }
                catch
                {
                    throw "Failed to load GitHub configuration helpers from '$dependencyPath': $($_.Exception.Message)"
                }
            }
        }

        Import-GitHubConfigurationHelpersIfNeeded
        $helpers = $script:PwshProfileGitHubConfigurationHelpers
        $maxRetryCount = $helpers.DefaultRetryCount
        $initialRetryDelaySeconds = $helpers.DefaultInitialRetryDelaySeconds
        $resolvedScope = $Scope

        switch ($resolvedScope)
        {
            'Repository'
            {
                if ($PSBoundParameters.ContainsKey('Environment'))
                {
                    throw 'Use -Scope Environment when specifying -Environment.'
                }

                if ($PSBoundParameters.ContainsKey('Organization'))
                {
                    throw 'Use -Scope Organization when specifying -Organization.'
                }
            }
            'Environment'
            {
                if (-not $PSBoundParameters.ContainsKey('Repository'))
                {
                    throw '-Scope Environment requires -Repository.'
                }

                if (-not $PSBoundParameters.ContainsKey('Environment'))
                {
                    throw '-Scope Environment requires -Environment.'
                }

                if ($PSBoundParameters.ContainsKey('Organization'))
                {
                    throw '-Scope Environment does not support -Organization.'
                }
            }
            'Organization'
            {
                if (-not $PSBoundParameters.ContainsKey('Organization'))
                {
                    throw '-Scope Organization requires -Organization.'
                }

                if ($PSBoundParameters.ContainsKey('Repository'))
                {
                    throw '-Scope Organization does not support -Repository.'
                }

                if ($PSBoundParameters.ContainsKey('Environment'))
                {
                    throw '-Scope Organization does not support -Environment.'
                }
            }
        }

        if ($SelectedRepository -and $resolvedScope -ne 'Organization')
        {
            throw '-SelectedRepository is supported only for -Scope Organization.'
        }

        if ($Visibility -and $resolvedScope -ne 'Organization')
        {
            throw '-Visibility is supported only for -Scope Organization.'
        }

        if ($Visibility -eq 'selected' -and -not $SelectedRepository)
        {
            throw "Visibility 'selected' requires -SelectedRepository."
        }

        if ($PSBoundParameters.ContainsKey('SelectedRepository') -and $Visibility -and $Visibility -ne 'selected')
        {
            throw "-SelectedRepository requires '-Visibility selected'. Specify '-Visibility selected' or omit -Visibility."
        }

        if ($PSBoundParameters.ContainsKey('SelectedRepository'))
        {
            $SelectedRepository = & $helpers.NormalizeSelectedRepositories `
                -Repositories $SelectedRepository `
                -Organization $Organization `
                -RequireOwnerRepoFormat:$false
        }

        $variableContext = & $helpers.GetVariableContext `
            -Scope $resolvedScope `
            -Repository $Repository `
            -Environment $Environment `
            -Organization $Organization

        $transport = & $helpers.ResolveTransport
        $authContext = & $helpers.ResolveAuthContext `
            -Token $Token `
            -TokenEnvironmentVariableName $TokenEnvironmentVariableName `
            -RequireToken:($transport.Name -ne 'GhCli')

        $variablePath = & $helpers.GetSingleItemPath -CollectionPath $variableContext.CollectionPath -Name $Name
        $existingVariable = & $helpers.TryGetGitHubResource `
            -Path $variablePath `
            -BaseUri $variableContext.ApiBaseUri `
            -Transport $transport `
            -AuthContext $authContext `
            -MaxRetryCount $maxRetryCount `
            -InitialRetryDelaySeconds $initialRetryDelaySeconds `
            -Activity "Get GitHub variable $Name"
    }

    process
    {
        if ($existingVariable.Found -and "$($existingVariable.Resource.value)" -eq $Value)
        {
            return & $helpers.NewOperationResult -TypeName 'GitHub.VariableSetResult' -Properties @{
                Name = $Name
                Scope = $variableContext.Scope
                Target = $variableContext.DisplayTarget
                Status = 'Unchanged'
                Changed = $false
                AlreadyExists = $true
                UsedForce = $false
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "Variable '$Name' already has the requested value."
            }
        }

        if ($existingVariable.Found -and -not $Force)
        {
            return & $helpers.NewOperationResult -TypeName 'GitHub.VariableSetResult' -Properties @{
                Name = $Name
                Scope = $variableContext.Scope
                Target = $variableContext.DisplayTarget
                Status = 'Skipped'
                Changed = $false
                AlreadyExists = $true
                UsedForce = $false
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "Variable '$Name' already exists for $($variableContext.DisplayTarget). Use -Force to overwrite it."
            }
        }

        $action = if ($existingVariable.Found) { 'Update GitHub variable' } else { 'Create GitHub variable' }
        if (-not $PSCmdlet.ShouldProcess("$($variableContext.DisplayTarget) :: $Name", $action))
        {
            return & $helpers.NewOperationResult -TypeName 'GitHub.VariableSetResult' -Properties @{
                Name = $Name
                Scope = $variableContext.Scope
                Target = $variableContext.DisplayTarget
                Status = 'WhatIf'
                Changed = $false
                AlreadyExists = $existingVariable.Found
                UsedForce = $Force.IsPresent
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "$action skipped by WhatIf."
            }
        }

        try
        {
            $body = @{
                name = $Name
                value = $Value
            }

            if ($variableContext.Scope -eq 'Organization')
            {
                $shouldIncludeVisibility = $Visibility -or $SelectedRepository -or -not $existingVariable.Found
                if ($shouldIncludeVisibility)
                {
                    $body['visibility'] = if ($Visibility)
                    {
                        $Visibility
                    }
                    elseif ($SelectedRepository)
                    {
                        'selected'
                    }
                    else
                    {
                        'private'
                    }
                }

                if ($SelectedRepository)
                {
                    $body['selected_repository_ids'] = & $helpers.ResolveSelectedRepositoryIds `
                        -Repositories $SelectedRepository `
                        -Organization $Organization `
                        -Transport $transport `
                        -AuthContext $authContext `
                        -MaxRetryCount $maxRetryCount `
                        -InitialRetryDelaySeconds $initialRetryDelaySeconds
                }
            }

            $method = if ($existingVariable.Found) { 'PATCH' } else { 'POST' }
            $path = if ($existingVariable.Found) { $variablePath } else { $variableContext.CollectionPath }

            $null = & $helpers.InvokeGitHubRequest `
                -Method $method `
                -BaseUri $variableContext.ApiBaseUri `
                -Path $path `
                -Transport $transport `
                -AuthContext $authContext `
                -Body $body `
                -MaxRetryCount $maxRetryCount `
                -InitialRetryDelaySeconds $initialRetryDelaySeconds `
                -Activity "$action $Name" `
                -SensitiveValues @()

            return & $helpers.NewOperationResult -TypeName 'GitHub.VariableSetResult' -Properties @{
                Name = $Name
                Scope = $variableContext.Scope
                Target = $variableContext.DisplayTarget
                Status = if ($existingVariable.Found) { 'Updated' } else { 'Created' }
                Changed = $true
                AlreadyExists = $existingVariable.Found
                UsedForce = $Force.IsPresent
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = if ($existingVariable.Found) { "Variable '$Name' was updated." } else { "Variable '$Name' was created." }
            }
        }
        catch
        {
            $friendlyMessage = & $helpers.GetFriendlyErrorMessage `
                -Operation 'set variable' `
                -Name $Name `
                -Target $variableContext.DisplayTarget `
                -Exception $_.Exception

            throw $friendlyMessage
        }
    }
}
