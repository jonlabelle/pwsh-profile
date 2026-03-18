function Set-GitHubVariable
{
    <#
    .SYNOPSIS
        Creates or updates a GitHub variable across repository, environment, and organization scopes.

    .DESCRIPTION
        Sets a GitHub variable using the GitHub CLI-backed API transport when available and falls back
        to direct REST API requests otherwise. Existing variables are updated only when -Force is used,
        unless the current value already matches the requested value.

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

        Variables are not encrypted by GitHub like secrets are, so this parameter accepts plain text.
        GitHub Actions configuration variables are intended for non-secret configuration values that
        workflows can reference, such as `${{ vars.NAME }}`.

    .PARAMETER Scope
        The GitHub variable scope. Valid values are Repository, Environment, and Organization.

        Meanings:
        - Repository: a repository-level variable for one repository
        - Environment: an environment-level variable for one deployment environment in a repository
        - Organization: an organization-level variable that can be shared with repositories

        This is the primary scope selector for the command. It is required so the target type is
        always explicit.

    .PARAMETER Repository
        The target repository in OWNER/REPO or HOST/OWNER/REPO format.

        This targets a repository-scoped variable. Repository variables are available only to the
        specified repository.

        When -Scope Repository is used and -Repository is omitted, the current Git repository origin
        is used. When -Scope Environment is used, -Repository is required.

    .PARAMETER Environment
        The deployment environment name for environment variables.

        This parameter is only valid for environment-scoped variables and requires -Repository.

        Environment variables belong to a single named environment within the repository and are
        intended for jobs that reference that environment.

        GitHub environment names:
        - Are not case sensitive
        - May not exceed 255 characters
        - Must be unique within the repository

        GitHub REST endpoints require environment names to be URL-encoded. This function handles
        that automatically, so names containing `/` are supported.

    .PARAMETER Organization
        The target organization for organization variables.

        This targets an organization-scoped variable. Organization variables can be shared with
        repositories in the organization according to the access policy set by -Visibility and
        -SelectedRepository. When -Scope Organization is used, -Organization is required.

    .PARAMETER Visibility
        Organization variable visibility. Valid values are all, private, and selected.

        Meanings:
        - all: every repository in the organization can use the variable
        - private: only private repositories in the organization can use the variable
        - selected: only repositories listed in -SelectedRepository can use the variable

        When -SelectedRepository is used and -Visibility is omitted, visibility is treated as selected.

    .PARAMETER SelectedRepository
        The repositories that can access an organization variable.

        This is the repository allow-list used when an organization variable has selected visibility.
        Bare repository names are resolved relative to -Organization for REST API fallback.

    .PARAMETER Force
        Overwrites an existing variable when the current value differs.

        If the existing value already matches the requested value, the function returns Unchanged
        and does not require -Force.

    .PARAMETER Token
        Optional GitHub personal access token as a SecureString.

        When omitted, the function checks the environment variable named by
        -TokenEnvironmentVariableName. If the GitHub CLI is installed, its existing authenticated
        session can also be used when no token is supplied.

    .PARAMETER TokenEnvironmentVariableName
        The environment variable name to check for a GitHub token when -Token is not supplied.

        Defaults to GH_TOKEN. The named environment variable is used for `gh` authentication and REST
        fallback when -Token is not supplied.

    .EXAMPLE
        PS > Set-GitHubVariable -Name 'DOTNET_VERSION' -Value '8.0.x' -Scope Repository -Repository 'octo-org/service-api'

        Creates a repository variable.

    .EXAMPLE
        PS > Set-GitHubVariable -Name 'DEPLOY_RING' -Value 'production' -Scope Environment -Repository 'octo-org/service-api' -Environment 'Production'

        Creates an environment variable for the Production deployment environment.

    .EXAMPLE
        PS > Set-GitHubVariable -Name 'REGION' -Value 'us-east-1' -Scope Organization -Organization 'octo-org' -Visibility selected -SelectedRepository 'app1', 'app2'

        Creates an organization variable that is visible only to selected repositories.

    .EXAMPLE
        PS > Set-GitHubVariable -Name 'FEATURE_FLAG' -Value 'enabled' -Scope Organization -Organization 'octo-org' -Force

        Overwrites an existing organization variable.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > Set-GitHubVariable -Name 'BUILD_CONFIGURATION' -Value 'Release' -Scope Repository -Repository 'octo-org/service-api' -Token $token -WhatIf

        Shows what would happen without modifying the variable.

    .OUTPUTS
        GitHub.VariableSetResult

        Returns a summary object with status, target scope, transport used, and whether the variable changed.

    .NOTES
        Organization variables default to private visibility when they are created without explicit visibility settings.
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
                    throw "Use -Scope Environment when specifying -Environment."
                }

                if ($PSBoundParameters.ContainsKey('Organization'))
                {
                    throw "Use -Scope Organization when specifying -Organization."
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
