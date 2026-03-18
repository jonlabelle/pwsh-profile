function Remove-GitHubVariable
{
    <#
    .SYNOPSIS
        Removes a GitHub variable from repository, environment, or organization scope.

    .DESCRIPTION
        Removes a GitHub variable using the GitHub CLI-backed API transport when available and falls
        back to direct REST API requests otherwise. Missing variables are treated as an idempotent no-op.

    .PARAMETER Name
        The GitHub variable name to remove.

        Configuration variable names:
        - Can contain only letters, numbers, and underscores
        - Cannot start with a number
        - Cannot start with the GITHUB_ prefix
        - Are case-insensitive when referenced by GitHub

    .PARAMETER Repository
        The target repository in OWNER/REPO or HOST/OWNER/REPO format.

        When omitted for repository and environment scopes, the current Git repository origin is used.

    .PARAMETER Environment
        The deployment environment name for environment variables.

        This parameter is only valid for environment-scoped variables and requires -Repository.

        GitHub environment names:
        - Are not case sensitive
        - May not exceed 255 characters
        - Must be unique within the repository

        GitHub REST endpoints require environment names to be URL-encoded. This function handles
        that automatically, so names containing `/` are supported.

    .PARAMETER Organization
        The target organization for organization variables.

    .PARAMETER Token
        Optional GitHub personal access token as a SecureString.

    .PARAMETER TokenEnvironmentVariableName
        The environment variable name to check for a GitHub token when -Token is not supplied.

        Defaults to GH_TOKEN.

    .EXAMPLE
        PS > Remove-GitHubVariable -Name 'DOTNET_VERSION' -Repository 'octo-org/service-api'

        Removes a repository variable.

    .EXAMPLE
        PS > Remove-GitHubVariable -Name 'DEPLOY_RING' -Repository 'octo-org/service-api' -Environment 'Production'

        Removes an environment variable.

    .EXAMPLE
        PS > Remove-GitHubVariable -Name 'REGION' -Organization 'octo-org' -WhatIf

        Shows what would happen before removing an organization variable.

    .OUTPUTS
        GitHub.VariableRemoveResult

        Returns a summary object with status, target scope, transport used, and whether the variable changed.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Repository')]
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

        [Parameter(ParameterSetName = 'Repository')]
        [Parameter(Mandatory, ParameterSetName = 'Environment')]
        [String]$Repository,

        [Parameter(Mandatory, ParameterSetName = 'Environment')]
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

        [Parameter(Mandatory, ParameterSetName = 'Organization')]
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
        $variableContext = & $helpers.GetVariableContext `
            -ParameterSetName $PSCmdlet.ParameterSetName `
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
