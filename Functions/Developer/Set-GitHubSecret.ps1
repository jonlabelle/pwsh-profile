function Set-GitHubSecret
{
    <#
    .SYNOPSIS
        Creates or updates a GitHub secret across repository, environment, organization, or user scopes.

    .DESCRIPTION
        Sets a GitHub secret by using the GitHub CLI. Existing secrets are never overwritten unless
        -Force is specified, so repeated calls stay idempotent.

        The function supports:
        - Repository, environment, organization, and user secret scopes
        - Actions, Codespaces, and Dependabot secret applications where applicable
        - Secure PAT input via -Token with fallback to GH_TOKEN (or another environment variable name)
        - -WhatIf/-Confirm through ShouldProcess
        - Exponential backoff retries for transient failures

        Secret operations require the GitHub CLI (gh). This function intentionally does not use a Python-based
        encryption fallback.

    .PARAMETER Name
        The name of the GitHub secret.

        GitHub secret names are typically uppercase with underscores, for example:
        - BUILD_TOKEN
        - AZURE_CLIENT_SECRET
        - NPM_AUTH_TOKEN

    .PARAMETER Value
        The secret value to store.

        Use Read-Host -AsSecureString or ConvertTo-SecureString to avoid adding sensitive data to
        shell history. The secure string is converted to plain text only for the outbound GitHub call.

    .PARAMETER Repository
        The target repository in OWNER/REPO or HOST/OWNER/REPO format.

        When omitted for repository and environment scopes, the current Git repository origin is used.

        Examples:
        - octo-org/service-api
        - github.example.com/platform/service-api

    .PARAMETER Environment
        The deployment environment name for environment secrets.

        This parameter is only valid for environment-scoped secrets and requires -Repository.
        Environment secrets always target GitHub Actions.

    .PARAMETER Organization
        The target organization for organization secrets.

        This parameter is only valid for organization-scoped secrets.

    .PARAMETER User
        Targets the authenticated user's Codespaces secrets.

        User secrets are only valid for Codespaces and cannot be combined with -Organization or -Environment.

    .PARAMETER Application
        The secret application. Valid values are actions, codespaces, and dependabot.

        Typical combinations:
        - Repository scope: actions, codespaces, or dependabot
        - Environment scope: actions only
        - Organization scope: actions, codespaces, or dependabot
        - User scope: codespaces only

    .PARAMETER Visibility
        Organization secret visibility. Valid values are all, private, and selected.

        This parameter is only valid for organization secrets.
        When -SelectedRepository is used and -Visibility is omitted, visibility is treated as selected.

    .PARAMETER SelectedRepository
        The repositories that can access an organization or user secret.

        For organization secrets, you can use bare repository names such as 'app1' alongside -Organization.
        For user secrets, use OWNER/REPO format.

    .PARAMETER NoRepositoriesSelected
        Creates an organization secret that is not available to any repositories.

        This is only valid for organization secrets and cannot be combined with -SelectedRepository.

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
        such as GITHUB_ADMIN_TOKEN.

    .PARAMETER MaxRetryCount
        The number of retry attempts for transient failures.

        Retries use exponential backoff and apply to transient API and network failures only.

    .PARAMETER InitialRetryDelaySeconds
        The initial retry delay in seconds.

        Exponential backoff is capped at 60 seconds regardless of the retry count.

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
        PS > Set-GitHubSecret -Name 'DEVCONTAINER_PAT' -Value $value -User

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

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Set-GitHubSecret.ps1
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Repository')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [SecureString]$Value,

        [Parameter(ParameterSetName = 'Repository')]
        [Parameter(Mandatory, ParameterSetName = 'Environment')]
        [String]$Repository,

        [Parameter(Mandatory, ParameterSetName = 'Environment')]
        [String]$Environment,

        [Parameter(Mandatory, ParameterSetName = 'Organization')]
        [ValidateNotNullOrEmpty()]
        [String]$Organization,

        [Parameter(Mandatory, ParameterSetName = 'User')]
        [Switch]$User,

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
        [String]$TokenEnvironmentVariableName = 'GH_TOKEN',

        [Parameter()]
        [ValidateRange(0, 10)]
        [Int]$MaxRetryCount = 3,

        [Parameter()]
        [ValidateRange(1, 60)]
        [Int]$InitialRetryDelaySeconds = 2
    )

    begin
    {
        function Import-GitHubConfigurationHelpersIfNeeded
        {
            if (-not (Get-Variable -Name 'PwshProfileGitHubConfigurationHelpers' -Scope Script -ErrorAction SilentlyContinue))
            {
                $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Private/GitHubConfigurationHelpers.ps1'
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

        if ($SelectedRepository -and $PSCmdlet.ParameterSetName -notin @('Organization', 'User'))
        {
            throw '-SelectedRepository is supported only for organization and user secrets.'
        }

        if ($Visibility -and $PSCmdlet.ParameterSetName -ne 'Organization')
        {
            throw '-Visibility is supported only for organization secrets.'
        }

        if ($NoRepositoriesSelected -and $PSCmdlet.ParameterSetName -ne 'Organization')
        {
            throw '-NoRepositoriesSelected is supported only for organization secrets.'
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
            -ParameterSetName $PSCmdlet.ParameterSetName `
            -Repository $Repository `
            -Environment $Environment `
            -Organization $Organization `
            -User $User.IsPresent `
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
            -MaxRetryCount $MaxRetryCount `
            -InitialRetryDelaySeconds $InitialRetryDelaySeconds `
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
            $ghArguments = @('secret', 'set', $Name) + $secretContext.GhTargetArguments + @('--body', $plainTextValue)

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

            $null = & $helpers.InvokeGhCommand `
                -Arguments $ghArguments `
                -AuthContext $authContext `
                -MaxRetryCount $MaxRetryCount `
                -InitialRetryDelaySeconds $InitialRetryDelaySeconds `
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
