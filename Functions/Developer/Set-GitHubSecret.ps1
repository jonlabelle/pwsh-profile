function Set-GitHubSecret
{
    <#
    .SYNOPSIS
        Creates or updates a GitHub secret at an explicit repository, environment, organization, or user scope.

    .DESCRIPTION
        Creates or updates a GitHub secret by using the GitHub CLI. Scope selection is always explicit
        through the required -Scope parameter.

        Repository scope can omit -Repository and use the current Git repository's origin remote.
        Environment, organization, and user scopes require their matching target parameters.

        Existing secrets are never overwritten unless -Force is specified, so repeated calls stay
        idempotent.

        The function supports:
        - Repository, environment, organization, and user secret scopes via -Scope
        - Actions, Codespaces, and Dependabot secret applications where applicable
        - Secure PAT input via -Token with fallback to GH_TOKEN (or another environment variable name)
        - -WhatIf/-Confirm through ShouldProcess
        - Exponential backoff retries for transient failures

        Secret operations require the GitHub CLI (gh). This function intentionally does not use a Python-based
        encryption fallback.

    .PARAMETER Name
        The name of the GitHub secret.

        Secret names:
        - Can contain only letters, numbers, and underscores
        - Cannot start with a number
        - Cannot start with the GITHUB_ prefix
        - Are case-insensitive when referenced by GitHub

        GitHub secret names are typically uppercase with underscores, for example:
        - BUILD_TOKEN
        - AZURE_CLIENT_SECRET
        - NPM_AUTH_TOKEN
        - DEVCONTAINER_PAT

    .PARAMETER Value
        The secret value to store.

        Use Read-Host -AsSecureString or ConvertTo-SecureString to avoid adding sensitive data to
        shell history. The secure string is converted to plain text only for the outbound GitHub call
        and is sent to `gh` over standard input so it is not exposed in process arguments. The `gh`
        CLI encrypts the value locally before it is sent to GitHub.

        GitHub secret values are limited to 48 KB in size.

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
        access policy set by -Visibility and -SelectedRepository.

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

        Use these patterns:
        - Actions secret: omit -Application or specify -Application actions
        - Codespaces secret: specify -Application codespaces for repository or organization scope
        - Dependabot secret: specify -Application dependabot for repository or organization scope
        - User secret: use -Scope User, which always targets Codespaces

        Specify the same application when updating an existing secret that was originally created for
        a non-default application such as dependabot or codespaces.

    .PARAMETER Visibility
        Organization secret visibility. Valid values are all, private, and selected.

        Supported only with -Scope Organization.

        Meanings:
        - all: every repository in the organization can use the secret
        - private: only private repositories in the organization can use the secret
        - selected: only repositories listed in -SelectedRepository can use the secret

        If -Visibility is omitted for an organization secret, GitHub defaults to private visibility.
        When -SelectedRepository is used and -Visibility is omitted, GitHub treats the access policy
        as selected visibility.

    .PARAMETER SelectedRepository
        The repositories that can access an organization or user secret.

        Supported only with -Scope Organization and -Scope User.

        For organization secrets, this is the repository allow-list used when visibility is selected.
        When -Organization is also supplied, you can use bare repository names such as 'app1'.

        For user-scope Codespaces secrets, this is the list of repositories whose codespaces can use the
        account-level secret. Use OWNER/REPO format.

    .PARAMETER NoRepositoriesSelected
        Creates an organization secret that is not available to any repositories.

        Supported only with -Scope Organization.

        This parameter cannot be combined with -SelectedRepository. Use it when you want to create
        the secret now but leave repository access disabled until access is granted later.

    .PARAMETER Force
        Overwrites an existing secret.

        Without -Force, existing secrets are skipped to keep the function idempotent. Because GitHub
        does not let clients read secret values back, an existing secret is treated as protected state
        and is not overwritten unless you opt in with -Force.

        Result behavior:
        - Existing secret + no -Force: Skipped
        - Existing secret + -Force: Updated
        - Missing secret: Created

    .PARAMETER Token
        Optional GitHub personal access token as a SecureString.

        If supplied, the token is injected only for the outbound `gh` call and is never written to
        command output.

        When omitted, the function checks the environment variable named by
        -TokenEnvironmentVariableName. If neither is supplied, an existing authenticated `gh`
        session can still be used.

    .PARAMETER TokenEnvironmentVariableName
        The environment variable name to check for a GitHub token when -Token is not supplied.

        Defaults to GH_TOKEN.

        This environment variable is read only when -Token is not supplied. Use it when automation
        stores the GitHub token under a non-default name such as GITHUB_ADMIN_TOKEN.

    .EXAMPLE
        PS > $value = Read-Host -AsSecureString
        PS > Set-GitHubSecret -Name 'MY_SECRET' -Value $value -Scope Repository

        Creates a repository-level Actions secret for the current Git repository.

    .EXAMPLE
        PS > $value = ConvertTo-SecureString $env:CODESPACES_TOKEN -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'DEVCONTAINER_PAT' -Value $value -Scope Repository -Repository 'octo-org/service-api' -Application codespaces

        Creates a repository-level Codespaces secret.

    .EXAMPLE
        PS > $value = ConvertTo-SecureString $env:DEPENDABOT_NUGET_TOKEN -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'NUGET_AUTH_TOKEN' -Value $value -Scope Repository -Repository 'octo-org/service-api' -Application dependabot -Force

        Overwrites an existing repository-level Dependabot secret.

    .EXAMPLE
        PS > $value = ConvertTo-SecureString $env:MY_SECRET -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'MY_SECRET' -Value $value -Scope Organization -Organization 'octo-org' -Visibility selected -SelectedRepository 'app1', 'app2'

        Creates an organization-level Actions secret restricted to specific repositories.

    .EXAMPLE
        PS > $value = ConvertTo-SecureString $env:CODESPACES_BOOTSTRAP -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'CODESPACES_BOOTSTRAP' -Value $value -Scope Organization -Organization 'octo-org' -Application codespaces -Visibility all

        Creates an organization-level Codespaces secret.

    .EXAMPLE
        PS > $value = Read-Host -AsSecureString
        PS > Set-GitHubSecret -Name 'DEPLOY_TOKEN' -Value $value -Scope Environment -Repository 'octo-org/service-api' -Environment 'Production'

        Creates or updates a production environment Actions secret for a repository.

    .EXAMPLE
        PS > $value = Read-Host -AsSecureString
        PS > Set-GitHubSecret -Name 'ORG_BOOTSTRAP_SECRET' -Value $value -Scope Organization -Organization 'octo-org' -NoRepositoriesSelected

        Creates an organization secret that currently has no repository access.

    .EXAMPLE
        PS > $value = ConvertTo-SecureString $env:CODESPACES_TOKEN -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'DEVCONTAINER_PAT' -Value $value -Scope User -SelectedRepository 'octo-org/service-api', 'octo-org/web-app'

        Creates a user-level Codespaces secret that is available only to the listed repositories.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > $value = ConvertTo-SecureString $env:BUILD_SECRET -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'BUILD_SECRET' -Value $value -Scope Organization -Organization 'octo-org' -Token $token -WhatIf

        Shows what would happen without changing the secret.

    .EXAMPLE
        PS > $value = ConvertTo-SecureString $env:CI_SECRET -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'CI_SECRET' -Value $value -Scope Repository -Repository 'octo-org/service-api' -TokenEnvironmentVariableName 'GITHUB_ADMIN_TOKEN'

        Reads the GitHub token from a non-default environment variable.

    .OUTPUTS
        GitHub.SecretSetResult

        Returns a summary object with status, target scope, resolved application, transport used,
        and whether the secret changed.

    .NOTES
        -Scope is required for all GitHub helper functions in this module family.
        Secret operations require the GitHub CLI (gh) to be installed and available in PATH.
        Secret values are passed to `gh secret set` through standard input, not command-line arguments.
        The GitHub CLI performs local encryption before sending secret values to GitHub.
        GitHub does not return secret values, so overwrite decisions are name-based plus -Force.

    .LINK
        https://cli.github.com/manual/gh_secret_set

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Set-GitHubSecret.ps1
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
        [ValidateNotNull()]
        [SecureString]$Value,

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
        [ValidateSet('all', 'private', 'selected')]
        [String]$Visibility,

        [Parameter()]
        [String[]]$SelectedRepository,

        [Parameter()]
        [Switch]$NoRepositoriesSelected,

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
            'User'
            {
                if ($PSBoundParameters.ContainsKey('Repository'))
                {
                    throw '-Scope User does not support -Repository. Use -SelectedRepository to restrict repository access.'
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

        if ($SelectedRepository -and $resolvedScope -notin @('Organization', 'User'))
        {
            throw '-SelectedRepository is supported only for -Scope Organization and -Scope User.'
        }

        if ($Visibility -and $resolvedScope -ne 'Organization')
        {
            throw '-Visibility is supported only for -Scope Organization.'
        }

        if ($NoRepositoriesSelected -and $resolvedScope -ne 'Organization')
        {
            throw '-NoRepositoriesSelected is supported only for -Scope Organization.'
        }

        if ($NoRepositoriesSelected -and $SelectedRepository)
        {
            throw 'Use either -NoRepositoriesSelected or -SelectedRepository, not both.'
        }

        if ($Visibility -eq 'selected' -and -not $SelectedRepository)
        {
            throw "Visibility 'selected' requires -SelectedRepository."
        }

        if ($PSBoundParameters.ContainsKey('SelectedRepository') -and $resolvedScope -eq 'Organization' -and $Visibility -and $Visibility -ne 'selected')
        {
            throw "-SelectedRepository for organization secrets requires '-Visibility selected'. Specify '-Visibility selected' or omit -Visibility."
        }

        if ($PSBoundParameters.ContainsKey('SelectedRepository'))
        {
            $SelectedRepository = & $helpers.NormalizeSelectedRepositories `
                -Repositories $SelectedRepository `
                -Organization $Organization `
                -RequireOwnerRepoFormat:($resolvedScope -eq 'User')
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

        $plainTextValueForValidation = & $helpers.ConvertSecureStringToPlainText $Value
        try
        {
            & $helpers.AssertValidGitHubSecretValue -Value $plainTextValueForValidation
        }
        finally
        {
            $plainTextValueForValidation = $null
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
        if ($existingSecret.Found -and -not $Force)
        {
            return & $helpers.NewOperationResult -TypeName 'GitHub.SecretSetResult' -Properties @{
                Name = $Name
                Scope = $secretContext.Scope
                Application = $secretContext.Application
                Target = $secretContext.DisplayTarget
                Status = 'Skipped'
                Changed = $false
                AlreadyExists = $true
                UsedForce = $false
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "Secret '$Name' already exists for $($secretContext.DisplayTarget). Use -Force to overwrite it."
            }
        }

        $action = if ($existingSecret.Found) { 'Update GitHub secret' } else { 'Create GitHub secret' }
        if (-not $PSCmdlet.ShouldProcess("$($secretContext.DisplayTarget) :: $Name", $action))
        {
            return & $helpers.NewOperationResult -TypeName 'GitHub.SecretSetResult' -Properties @{
                Name = $Name
                Scope = $secretContext.Scope
                Application = $secretContext.Application
                Target = $secretContext.DisplayTarget
                Status = 'WhatIf'
                Changed = $false
                AlreadyExists = $existingSecret.Found
                UsedForce = $Force.IsPresent
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "$action skipped by WhatIf."
            }
        }

        $plainTextValue = & $helpers.ConvertSecureStringToPlainText $Value
        try
        {
            $ghArguments = @('secret', 'set', $Name) + $secretContext.GhTargetArguments

            if ($Visibility)
            {
                $ghArguments += @('--visibility', $Visibility)
            }

            if ($SelectedRepository)
            {
                $ghArguments += @('--repos', ($SelectedRepository -join ','))
            }

            if ($NoRepositoriesSelected)
            {
                $ghArguments += '--no-repos-selected'
            }

            $null = & $helpers.InvokeGhCommandWithStandardInput `
                -Arguments $ghArguments `
                -StandardInputText $plainTextValue `
                -AuthContext $authContext `
                -MaxRetryCount $maxRetryCount `
                -InitialRetryDelaySeconds $initialRetryDelaySeconds `
                -Activity "$action $Name" `
                -SensitiveValues @($plainTextValue)

            return & $helpers.NewOperationResult -TypeName 'GitHub.SecretSetResult' -Properties @{
                Name = $Name
                Scope = $secretContext.Scope
                Application = $secretContext.Application
                Target = $secretContext.DisplayTarget
                Status = if ($existingSecret.Found) { 'Updated' } else { 'Created' }
                Changed = $true
                AlreadyExists = $existingSecret.Found
                UsedForce = $Force.IsPresent
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = if ($existingSecret.Found) { "Secret '$Name' was updated." } else { "Secret '$Name' was created." }
            }
        }
        catch
        {
            $friendlyMessage = & $helpers.GetFriendlyErrorMessage `
                -Operation 'set secret' `
                -Name $Name `
                -Target $secretContext.DisplayTarget `
                -Exception $_.Exception

            throw $friendlyMessage
        }
        finally
        {
            $plainTextValue = $null
        }
    }
}
