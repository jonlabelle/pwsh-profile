function Remove-GitHubSecret
{
    <#
    .SYNOPSIS
        Removes a GitHub secret from an explicit repository, environment, organization, or user scope.

    .DESCRIPTION
        Removes a GitHub secret by using the GitHub CLI. Scope selection is always explicit through
        the required -Scope parameter.

        Repository scope can omit -Repository and use the current Git repository's origin remote.
        Environment, organization, and user scopes require their matching target parameters.

        Missing secrets are treated as an idempotent no-op so repeated runs remain safe.

        Secret operations require the GitHub CLI (gh). This function intentionally does not use a
        Python-based encryption fallback.

    .PARAMETER Name
        The name of the GitHub secret to remove.

        Secret names:
        - Can contain only letters, numbers, and underscores
        - Cannot start with a number
        - Cannot start with the GITHUB_ prefix
        - Are case-insensitive when referenced by GitHub

    .PARAMETER Scope
        The GitHub secret scope. Valid values are Repository, Environment, Organization, and User.

        Meanings:
        - Repository: a repository-level secret for one repository
        - Environment: an environment-level secret for one deployment environment in a repository
        - Organization: an organization-level secret that can be shared with repositories
        - User: an account-level Codespaces secret for the authenticated user

        Companion parameter rules:
        - Repository: use -Scope Repository; -Repository is optional
        - Environment: use -Scope Environment; -Repository and -Environment are required
        - Organization: use -Scope Organization; -Organization is required
        - User: use -Scope User for a user-level Codespaces secret; -Repository, -Environment, and -Organization are not valid

        Use -Scope User instead of a separate user switch. It maps to GitHub's user-level
        Codespaces secret behavior.

    .PARAMETER Repository
        The target repository in OWNER/REPO or HOST/OWNER/REPO format.

        Supported with -Scope Repository and -Scope Environment.

        Repository secrets are available only to the specified repository. Environment secrets belong
        to a specific environment in the specified repository.

        When -Scope Repository is used and -Repository is omitted, the function tries to resolve the
        current Git repository's origin remote. If that cannot be determined, specify -Repository
        explicitly.

        Examples:
        - octo-org/service-api
        - github.example.com/platform/service-api

    .PARAMETER Environment
        The deployment environment name for environment secrets.

        Supported only with -Scope Environment and requires -Repository.

        Environment secrets always target GitHub Actions and belong to a single named environment
        within the repository. They are intended for jobs that reference that environment.

        GitHub environment names:
        - Are not case sensitive
        - May not exceed 255 characters
        - Must be unique within the repository

        GitHub REST endpoints require environment names to be URL-encoded. This function handles
        that automatically, so names containing spaces or `/` are supported.

    .PARAMETER Organization
        The target organization for organization secrets.

        Supported only with -Scope Organization.

        Organization secrets can be shared with repositories in the organization according to the
        access policy that was configured when the secret was created or last updated.

    .PARAMETER Application
        The secret application. Valid values are actions, codespaces, and dependabot.

        Meanings:
        - actions: the secret is available to GitHub Actions workflows
        - codespaces: the secret is available to GitHub Codespaces
        - dependabot: the secret is available to Dependabot

        If -Application is omitted, the function defaults to:
        - Repository scope: actions
        - Environment scope: actions
        - Organization scope: actions
        - User scope: codespaces

        Typical combinations:
        - Repository scope: actions, codespaces, or dependabot
        - Environment scope: actions only
        - Organization scope: actions, codespaces, or dependabot
        - User scope: codespaces only

        When deleting a secret for a non-default application such as dependabot or codespaces,
        specify the same -Application value that was used when the secret was created.

    .PARAMETER Token
        Optional GitHub personal access token as a SecureString.

        If supplied, the token is injected only for the outbound `gh` call and is never written to
        command output.

        When omitted, the function checks the environment variable named by
        -TokenEnvironmentVariableName. If the GitHub CLI is installed, its existing authenticated
        session can also be used when no token is supplied.

    .PARAMETER TokenEnvironmentVariableName
        The environment variable name to check for a GitHub token when -Token is not supplied.

        Defaults to GH_TOKEN.

        This environment variable is read only when -Token is not supplied. Use it when automation
        stores the GitHub token under a non-default name such as GITHUB_ADMIN_TOKEN.

    .EXAMPLE
        PS > Remove-GitHubSecret -Name 'MY_SECRET' -Scope Repository

        Removes a repository secret from the current Git repository.

    .EXAMPLE
        PS > Remove-GitHubSecret -Name 'DEPLOY_TOKEN' -Scope Environment -Repository 'octo-org/service-api' -Environment 'Production'

        Removes an environment secret.

    .EXAMPLE
        PS > Remove-GitHubSecret -Name 'DEVCONTAINER_PAT' -Scope User -WhatIf

        Shows what would happen before deleting a user-level Codespaces secret.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > Remove-GitHubSecret -Name 'NUGET_AUTH_TOKEN' -Scope Organization -Organization 'octo-org' -Application dependabot -Token $token

        Removes an organization-level Dependabot secret by using an explicit token.

    .EXAMPLE
        PS > Remove-GitHubSecret -Name 'CODESPACES_BOOTSTRAP' -Scope Organization -Organization 'octo-org' -Application codespaces

        Removes an organization-level Codespaces secret.

    .OUTPUTS
        GitHub.SecretRemoveResult

        Returns a summary object with status, target scope, resolved application, transport used,
        and whether the secret changed.

    .NOTES
        -Scope is required for all GitHub helper functions in this module family.
        Secret operations require the GitHub CLI (gh) to be installed and available in PATH.
        If the secret does not exist, the function returns an AlreadyAbsent result instead of failing.

    .LINK
        https://cli.github.com/manual/gh_secret_delete

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Remove-GitHubSecret.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if ($_ -match '^(?i:GITHUB_)')
            {
                throw "GitHub secret names cannot start with the 'GITHUB_' prefix."
            }

            if ($_ -notmatch '^(?![0-9])[A-Za-z0-9_]+$')
            {
                throw 'GitHub secret names may only contain letters, numbers, or underscores, and cannot start with a number.'
            }

            $true
        })]
        [String]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Repository', 'Environment', 'Organization', 'User')]
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
        [ValidateSet('actions', 'codespaces', 'dependabot')]
        [String]$Application,

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
            'User'
            {
                if ($PSBoundParameters.ContainsKey('Repository'))
                {
                    throw '-Scope User does not support -Repository.'
                }

                if ($PSBoundParameters.ContainsKey('Environment'))
                {
                    throw '-Scope User does not support -Environment.'
                }

                if ($PSBoundParameters.ContainsKey('Organization'))
                {
                    throw '-Scope User does not support -Organization.'
                }
            }
        }

        $secretContext = & $helpers.GetSecretContext `
            -Scope $resolvedScope `
            -Repository $Repository `
            -Environment $Environment `
            -Organization $Organization `
            -Application $Application

        $transport = & $helpers.ResolveTransport
        if ($transport.Name -ne 'GhCli')
        {
            throw 'GitHub secret operations require the GitHub CLI (gh) to be installed and available in PATH.'
        }

        $authContext = & $helpers.ResolveAuthContext `
            -Token $Token `
            -TokenEnvironmentVariableName $TokenEnvironmentVariableName `
            -RequireToken:$false

        $secretPath = & $helpers.GetSingleItemPath -CollectionPath $secretContext.MetadataCollectionPath -Name $Name
        $existingSecret = & $helpers.TryGetGitHubResource `
            -Path $secretPath `
            -BaseUri $secretContext.ApiBaseUri `
            -Transport $transport `
            -AuthContext $authContext `
            -MaxRetryCount $maxRetryCount `
            -InitialRetryDelaySeconds $initialRetryDelaySeconds `
            -Activity "Get GitHub secret $Name"
    }

    process
    {
        if (-not $existingSecret.Found)
        {
            return & $helpers.NewOperationResult -TypeName 'GitHub.SecretRemoveResult' -Properties @{
                Name = $Name
                Scope = $secretContext.Scope
                Application = $secretContext.Application
                Target = $secretContext.DisplayTarget
                Status = 'AlreadyAbsent'
                Changed = $false
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "Secret '$Name' does not exist for $($secretContext.DisplayTarget)."
            }
        }

        if (-not $PSCmdlet.ShouldProcess("$($secretContext.DisplayTarget) :: $Name", 'Remove GitHub secret'))
        {
            return & $helpers.NewOperationResult -TypeName 'GitHub.SecretRemoveResult' -Properties @{
                Name = $Name
                Scope = $secretContext.Scope
                Application = $secretContext.Application
                Target = $secretContext.DisplayTarget
                Status = 'WhatIf'
                Changed = $false
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = 'Secret removal skipped by WhatIf.'
            }
        }

        try
        {
            $ghArguments = @('secret', 'delete', $Name) + $secretContext.GhTargetArguments
            $null = & $helpers.InvokeGhCommand `
                -Arguments $ghArguments `
                -AuthContext $authContext `
                -MaxRetryCount $maxRetryCount `
                -InitialRetryDelaySeconds $initialRetryDelaySeconds `
                -Activity "Remove GitHub secret $Name"

            return & $helpers.NewOperationResult -TypeName 'GitHub.SecretRemoveResult' -Properties @{
                Name = $Name
                Scope = $secretContext.Scope
                Application = $secretContext.Application
                Target = $secretContext.DisplayTarget
                Status = 'Removed'
                Changed = $true
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "Secret '$Name' was removed."
            }
        }
        catch
        {
            $friendlyMessage = & $helpers.GetFriendlyErrorMessage `
                -Operation 'remove secret' `
                -Name $Name `
                -Target $secretContext.DisplayTarget `
                -Exception $_.Exception

            throw $friendlyMessage
        }
    }
}
