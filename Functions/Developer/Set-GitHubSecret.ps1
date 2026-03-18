function Set-GitHubSecret
{
    <#
    .SYNOPSIS
        Creates or updates a GitHub secret across repository, environment, organization, or user scopes.

    .DESCRIPTION
        Sets a GitHub secret by using the GitHub CLI. Existing secrets are never overwritten unless
        -Force is specified, so repeated calls stay idempotent.

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

    .PARAMETER Value
        The secret value to store.

        Use Read-Host -AsSecureString or ConvertTo-SecureString to avoid adding sensitive data to
        shell history. The secure string is converted to plain text only for the outbound GitHub call
        and is sent to `gh` over standard input so it is not exposed in process arguments.

        GitHub secret values are limited to 48 KB in size.

    .PARAMETER Scope
        The GitHub secret scope. Valid values are Repository, Environment, Organization, and User.

        Meanings:
        - Repository: a repository-level secret for one repository
        - Environment: an environment-level secret for one deployment environment in a repository
        - Organization: an organization-level secret that can be shared with repositories
        - User: an account-level Codespaces secret for the authenticated user

        This is the primary scope selector for the command. Use -Scope User instead of a separate
        user switch; it maps to GitHub's user-level Codespaces secret behavior.

        Repository is the default when -Scope is omitted. If you specify -Environment or
        -Organization without -Scope, the function infers Environment or Organization scope.

    .PARAMETER Repository
        The target repository in OWNER/REPO or HOST/OWNER/REPO format.

        This targets a repository-scoped secret. Repository secrets are available only to the
        specified repository.

        When omitted for repository scope, the current Git repository origin is used.
        When -Scope Environment is used, -Repository is required.

        Examples:
        - octo-org/service-api
        - github.example.com/platform/service-api

    .PARAMETER Environment
        The deployment environment name for environment secrets.

        This parameter is only valid for environment-scoped secrets and requires -Repository.
        Environment secrets always target GitHub Actions and belong to a single named environment
        within the repository. They are intended for jobs that reference that environment.

        GitHub environment names:
        - Are not case sensitive
        - May not exceed 255 characters
        - Must be unique within the repository

        GitHub REST endpoints require environment names to be URL-encoded. This function handles
        that automatically, so names containing `/` are supported.

    .PARAMETER Organization
        The target organization for organization secrets.

        This targets an organization-scoped secret. Organization secrets can be shared with
        repositories in the organization according to the access policy set by -Visibility and
        -SelectedRepository. When -Scope Organization is used, -Organization is required.

    .PARAMETER Application
        The secret application. Valid values are actions, codespaces, and dependabot.

        Meanings:
        - actions: the secret is available to GitHub Actions workflows
        - codespaces: the secret is available to GitHub Codespaces
        - dependabot: the secret is available to Dependabot

        At user scope, the application is fixed to Codespaces even when -Application is omitted.

        Typical combinations:
        - Repository scope: actions, codespaces, or dependabot
        - Environment scope: actions only
        - Organization scope: actions, codespaces, or dependabot
        - User scope: codespaces only

    .PARAMETER Visibility
        Organization secret visibility. Valid values are all, private, and selected.

        This parameter is only valid for organization secrets.
        Meanings:
        - all: every repository in the organization can use the secret
        - private: only private repositories in the organization can use the secret
        - selected: only repositories listed in -SelectedRepository can use the secret

        When -SelectedRepository is used and -Visibility is omitted, visibility is treated as selected.

    .PARAMETER SelectedRepository
        The repositories that can access an organization or user secret.

        For organization secrets, this is the repository allow-list used when visibility is selected.
        You can use bare repository names such as 'app1' alongside -Organization.

        For user-scope Codespaces secrets, this is the list of repositories whose codespaces can use the
        account-level secret. Use OWNER/REPO format.

    .PARAMETER NoRepositoriesSelected
        Creates an organization secret that is not available to any repositories.

        This is only valid for organization secrets and cannot be combined with -SelectedRepository.
        Use this when you want to create the secret now but leave its repository allow-list empty
        until access is granted later.

    .PARAMETER Force
        Overwrites an existing secret.

        Without -Force, existing secrets are skipped to keep the function idempotent. Because GitHub
        does not let clients read secret values back, an existing secret is treated as protected state
        and is not overwritten unless you opt in with -Force.

    .PARAMETER Token
        Optional GitHub personal access token as a SecureString.

        When omitted, the function checks the environment variable named by
        -TokenEnvironmentVariableName. If the GitHub CLI is installed, its existing authenticated
        session can also be used when no token is supplied.

    .PARAMETER TokenEnvironmentVariableName
        The environment variable name to check for a GitHub token when -Token is not supplied.

        Defaults to GH_TOKEN. Use this when your token is stored in a different environment variable,
        such as GITHUB_ADMIN_TOKEN. The named environment variable is used for both `gh` authentication
        injection and REST fallback where applicable.

    .EXAMPLE
        PS > $value = Read-Host -AsSecureString
        PS > Set-GitHubSecret -Name 'MY_SECRET' -Value $value -Repository 'octo-org/octo-repo'

        Creates a repository secret in octo-org/octo-repo.

    .EXAMPLE
        PS > $value = ConvertTo-SecureString $env:MY_SECRET -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'MY_SECRET' -Value $value -Organization 'octo-org' -Visibility selected -SelectedRepository 'app1', 'app2'

        Creates an organization secret restricted to specific repositories.

    .EXAMPLE
        PS > $value = Read-Host -AsSecureString
        PS > Set-GitHubSecret -Name 'DEPLOY_TOKEN' -Value $value -Repository 'octo-org/service-api' -Environment 'Production'

        Creates or updates a production environment secret for a repository.

    .EXAMPLE
        PS > $value = ConvertTo-SecureString $env:CODESPACES_TOKEN -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'DEVCONTAINER_PAT' -Value $value -Scope User

        Creates a user-level Codespaces secret.

    .EXAMPLE
        PS > $value = ConvertTo-SecureString $env:DEPENDABOT_NUGET_TOKEN -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'NUGET_AUTH_TOKEN' -Value $value -Organization 'octo-org' -Application dependabot -Force

        Overwrites an existing organization-level Dependabot secret.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > $value = ConvertTo-SecureString $env:BUILD_SECRET -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'BUILD_SECRET' -Value $value -Organization 'octo-org' -Token $token -WhatIf

        Shows what would happen without changing the secret.

    .EXAMPLE
        PS > $value = ConvertTo-SecureString $env:CI_SECRET -AsPlainText -Force
        PS > Set-GitHubSecret -Name 'CI_SECRET' -Value $value -Repository 'octo-org/service-api' -TokenEnvironmentVariableName 'GITHUB_ADMIN_TOKEN'

        Reads the GitHub token from a non-default environment variable.

    .OUTPUTS
        GitHub.SecretSetResult

        Returns a summary object with status, target scope, transport used, and whether the secret changed.

    .NOTES
        Secret operations require the GitHub CLI (gh) to be installed and available in PATH.
        Secret values are passed to `gh secret set` through standard input, not command-line arguments.

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

        [Parameter()]
        [ValidateSet('Repository', 'Environment', 'Organization', 'User')]
        [String]$Scope = 'Repository',

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
        $resolvedScope = if ($PSBoundParameters.ContainsKey('Scope'))
        {
            $Scope
        }
        elseif ($PSBoundParameters.ContainsKey('Organization'))
        {
            'Organization'
        }
        elseif ($PSBoundParameters.ContainsKey('Environment'))
        {
            'Environment'
        }
        else
        {
            'Repository'
        }

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
