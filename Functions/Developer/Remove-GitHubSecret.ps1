function Remove-GitHubSecret
{
    <#
    .SYNOPSIS
        Removes a GitHub secret from repository, environment, organization, or user scope.

    .DESCRIPTION
        Removes a GitHub secret by using the GitHub CLI. Missing secrets are treated as an idempotent
        no-op so repeated runs remain safe.

        Secret operations require the GitHub CLI (gh). This function intentionally does not use a
        Python-based encryption fallback.

    .PARAMETER Name
        The name of the GitHub secret to remove.

    .PARAMETER Repository
        The target repository in OWNER/REPO or HOST/OWNER/REPO format.

        When omitted for repository and environment scopes, the current Git repository origin is used.

    .PARAMETER Environment
        The deployment environment name for environment secrets.

        This parameter is only valid for environment-scoped secrets and requires -Repository.

    .PARAMETER Organization
        The target organization for organization secrets.

    .PARAMETER User
        Targets the authenticated user's Codespaces secrets.

    .PARAMETER Application
        The secret application. Valid values are actions, codespaces, and dependabot.

        Valid combinations depend on scope in the same way as Set-GitHubSecret.

    .PARAMETER Token
        Optional GitHub personal access token as a SecureString.

        When omitted, the function checks the environment variable named by
        -TokenEnvironmentVariableName. If the GitHub CLI is installed, its existing authenticated
        session can also be used when no token is supplied.

    .PARAMETER TokenEnvironmentVariableName
        The environment variable name to check for a GitHub token when -Token is not supplied.

        Defaults to GH_TOKEN.

    .PARAMETER MaxRetryCount
        The number of retry attempts for transient failures.

    .PARAMETER InitialRetryDelaySeconds
        The initial retry delay in seconds.

        Exponential backoff is capped at 60 seconds regardless of the retry count.

    .EXAMPLE
        PS > Remove-GitHubSecret -Name 'MY_SECRET' -Repository 'octo-org/octo-repo'

        Removes a repository secret.

    .EXAMPLE
        PS > Remove-GitHubSecret -Name 'DEPLOY_TOKEN' -Repository 'octo-org/service-api' -Environment 'Production'

        Removes an environment secret.

    .EXAMPLE
        PS > Remove-GitHubSecret -Name 'DEVCONTAINER_PAT' -User -WhatIf

        Shows what would happen before deleting a user-level Codespaces secret.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > Remove-GitHubSecret -Name 'NUGET_AUTH_TOKEN' -Organization 'octo-org' -Application dependabot -Token $token

        Removes an organization-level Dependabot secret by using an explicit token.

    .OUTPUTS
        GitHub.SecretRemoveResult

        Returns a summary object with status, target scope, transport used, and whether the secret changed.

    .NOTES
        If the secret does not exist, the function returns an AlreadyAbsent result instead of failing.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Repository')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

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
                -MaxRetryCount $MaxRetryCount `
                -InitialRetryDelaySeconds $InitialRetryDelaySeconds `
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
