function Remove-GitHubVariable
{
    <#
    .SYNOPSIS
        Removes a GitHub configuration variable from an explicit repository, environment, or organization scope.

    .DESCRIPTION
        Removes a GitHub configuration variable. Scope selection is always explicit through the
        required -Scope parameter.

        Repository scope can omit -Repository and use the current Git repository's origin remote.
        Environment and organization scopes require their matching target parameters.

        The function prefers the GitHub CLI-backed API transport when `gh` is available and falls
        back to direct REST API requests otherwise. Missing variables are treated as an idempotent
        no-op.

    .PARAMETER Name
        The GitHub variable name to remove.

        Configuration variable names:
        - Can contain only letters, numbers, and underscores
        - Cannot start with a number
        - Cannot start with the GITHUB_ prefix
        - Are case-insensitive when referenced by GitHub

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
        access policy configured on GitHub.

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
        PS > Remove-GitHubVariable -Name 'DOTNET_VERSION' -Scope Repository

        Removes a repository variable from the current Git repository.

    .EXAMPLE
        PS > Remove-GitHubVariable -Name 'DEPLOY_RING' -Scope Environment -Repository 'octo-org/service-api' -Environment 'Production'

        Removes an environment variable.

    .EXAMPLE
        PS > Remove-GitHubVariable -Name 'REGION' -Scope Organization -Organization 'octo-org' -WhatIf

        Shows what would happen before removing an organization variable.

    .EXAMPLE
        PS > Remove-GitHubVariable -Name 'PACKAGE_SOURCE' -Scope Organization -Organization 'octo-org' -TokenEnvironmentVariableName 'GITHUB_ADMIN_TOKEN'

        Reads the GitHub token from a non-default environment variable.

    .OUTPUTS
        GitHub.VariableRemoveResult

        Returns a summary object with status, target scope, transport used, and whether the variable
        changed.

    .NOTES
        -Scope is required for all GitHub helper functions in this module family.
        Variables prefer the GitHub CLI-backed transport and fall back to direct REST API requests.
        If the variable does not exist, the function returns an AlreadyAbsent result instead of failing.

    .LINK
        https://cli.github.com/manual/gh_variable_delete

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Remove-GitHubVariable.ps1
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
        if (-not $existingVariable.Found)
        {
            return & $helpers.NewOperationResult -TypeName 'GitHub.VariableRemoveResult' -Properties @{
                Name = $Name
                Scope = $variableContext.Scope
                Target = $variableContext.DisplayTarget
                Status = 'AlreadyAbsent'
                Changed = $false
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "Variable '$Name' does not exist for $($variableContext.DisplayTarget)."
            }
        }

        if (-not $PSCmdlet.ShouldProcess("$($variableContext.DisplayTarget) :: $Name", 'Remove GitHub variable'))
        {
            return & $helpers.NewOperationResult -TypeName 'GitHub.VariableRemoveResult' -Properties @{
                Name = $Name
                Scope = $variableContext.Scope
                Target = $variableContext.DisplayTarget
                Status = 'WhatIf'
                Changed = $false
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = 'Variable removal skipped by WhatIf.'
            }
        }

        try
        {
            $null = & $helpers.InvokeGitHubRequest `
                -Method 'DELETE' `
                -BaseUri $variableContext.ApiBaseUri `
                -Path $variablePath `
                -Transport $transport `
                -AuthContext $authContext `
                -Body $null `
                -MaxRetryCount $maxRetryCount `
                -InitialRetryDelaySeconds $initialRetryDelaySeconds `
                -Activity "Remove GitHub variable $Name" `
                -SensitiveValues @()

            return & $helpers.NewOperationResult -TypeName 'GitHub.VariableRemoveResult' -Properties @{
                Name = $Name
                Scope = $variableContext.Scope
                Target = $variableContext.DisplayTarget
                Status = 'Removed'
                Changed = $true
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "Variable '$Name' was removed."
            }
        }
        catch
        {
            $friendlyMessage = & $helpers.GetFriendlyErrorMessage `
                -Operation 'remove variable' `
                -Name $Name `
                -Target $variableContext.DisplayTarget `
                -Exception $_.Exception

            throw $friendlyMessage
        }
    }
}
