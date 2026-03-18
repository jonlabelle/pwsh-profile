<#
.SYNOPSIS
    Private shared helpers for the GitHub developer functions.

.DESCRIPTION
    This file is an internal implementation detail used by the following public functions:
    - Set-GitHubSecret
    - Remove-GitHubSecret
    - Set-GitHubVariable
    - Get-GitHubVariable
    - Remove-GitHubVariable

    It is intentionally not a public profile function:
    - The filename is not in Verb-Noun format
    - The filename does not contain a hyphen
    - It does not declare exported user-facing functions

    That naming is deliberate because the profile loader in
    Microsoft.PowerShell_profile.ps1 auto-loads only files that match `*-*.ps1`.
    Since this file is named `GitHubConfigurationHelpers.ps1`, it is ignored by the
    loader and will not appear as a top-level command in the session.

    Instead, each public GitHub function lazy-loads this file on demand via its local
    Import-GitHubConfigurationHelpersIfNeeded helper. That keeps the shared logic in one
    place without polluting the command surface or adding work to profile startup.

    The helper data is stored in the script-scoped
    `$script:PwshProfileGitHubConfigurationHelpers` variable as a collection of reusable
    script blocks and configuration values. Keeping the shared state behind a private
    variable also makes it straightforward for the public functions and unit tests to
    detect whether the helper has already been loaded.

.NOTES
    If you add more internal helper scripts under Functions/, keep them out of the
    auto-loader by avoiding the public Verb-Noun `*-*.ps1` naming pattern and load
    them explicitly from the public entry points that need them.
#>

$helperVariableName = 'PwshProfileGitHubConfigurationHelpers'

if (-not (Get-Variable -Name $helperVariableName -Scope Script -ErrorAction SilentlyContinue))
{
    $script:PwshProfileGitHubConfigurationHelpers = [ordered]@{
        DefaultRetryCount = 3
        DefaultInitialRetryDelaySeconds = 2
        MaxSecretSizeBytes = 48KB
        MaxBackoffSeconds = 60
    }

    $script:PwshProfileGitHubConfigurationHelpers.ConvertSecureStringToPlainText = {
        param([SecureString]$SecureString)

        if ($null -eq $SecureString)
        {
            return $null
        }

        $bstr = [IntPtr]::Zero
        try
        {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally
        {
            if ($bstr -ne [IntPtr]::Zero)
            {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.NewOperationResult = {
        param(
            [String]$TypeName,
            [Hashtable]$Properties
        )

        $result = [PSCustomObject]$Properties
        if ($TypeName)
        {
            $result.PSObject.TypeNames.Insert(0, $TypeName)
        }

        return $result
    }

    $script:PwshProfileGitHubConfigurationHelpers.GetUtf8ByteCount = {
        param([AllowNull()][String]$Value)

        if ($null -eq $Value)
        {
            return 0
        }

        return [System.Text.UTF8Encoding]::new($false).GetByteCount($Value)
    }

    $script:PwshProfileGitHubConfigurationHelpers.AssertValidGitHubSecretValue = {
        param([AllowNull()][String]$Value)

        $utf8ByteCount = & $script:PwshProfileGitHubConfigurationHelpers.GetUtf8ByteCount $Value
        if ($utf8ByteCount -gt $script:PwshProfileGitHubConfigurationHelpers.MaxSecretSizeBytes)
        {
            throw "GitHub secret values may not exceed 48 KB ($($script:PwshProfileGitHubConfigurationHelpers.MaxSecretSizeBytes) bytes)."
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.GetExceptionStatusCode = {
        param([System.Exception]$Exception)

        if ($null -eq $Exception)
        {
            return $null
        }

        if ($Exception.Data.Contains('StatusCode'))
        {
            return $Exception.Data['StatusCode']
        }

        $response = $Exception.Response
        if ($null -eq $response)
        {
            return $null
        }

        if ($response.StatusCode)
        {
            return [int]$response.StatusCode
        }

        return $null
    }

    $script:PwshProfileGitHubConfigurationHelpers.GetExceptionMessage = {
        param([System.Exception]$Exception)

        if ($null -eq $Exception)
        {
            return 'Unknown GitHub error.'
        }

        $errorDetails = $Exception.ErrorDetails
        if ($errorDetails -and -not [string]::IsNullOrWhiteSpace($errorDetails.Message))
        {
            return $errorDetails.Message.Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($Exception.Message))
        {
            return $Exception.Message.Trim()
        }

        return 'Unknown GitHub error.'
    }

    $script:PwshProfileGitHubConfigurationHelpers.TrimErrorMessage = {
        param([String]$Message)

        if ([string]::IsNullOrWhiteSpace($Message))
        {
            return 'Unknown GitHub error.'
        }

        $normalized = ($Message -replace '\s+', ' ').Trim()
        $patterns = @(
            '^gh:\s*',
            '^GraphQL:\s*',
            '^HTTP 404:\s*',
            '^HTTP 401:\s*',
            '^HTTP 403:\s*',
            '^HTTP 422:\s*'
        )

        foreach ($pattern in $patterns)
        {
            $normalized = $normalized -replace $pattern, ''
        }

        return $normalized.Trim()
    }

    $script:PwshProfileGitHubConfigurationHelpers.RedactSensitiveText = {
        param(
            [String]$Message,
            [String[]]$SensitiveValues
        )

        if ([string]::IsNullOrWhiteSpace($Message))
        {
            return $Message
        }

        $redactedMessage = $Message

        foreach ($sensitiveValue in @($SensitiveValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object Length -Descending -Unique))
        {
            $escapedValue = [Regex]::Escape($sensitiveValue)
            $redactedMessage = [Regex]::Replace($redactedMessage, $escapedValue, '[REDACTED]')
        }

        $tokenPatterns = @(
            '\bgh[pousr]_[A-Za-z0-9_]+\b',
            '\bgithub_pat_[A-Za-z0-9_]+\b'
        )

        foreach ($tokenPattern in $tokenPatterns)
        {
            $redactedMessage = [Regex]::Replace($redactedMessage, $tokenPattern, '[REDACTED]')
        }

        return $redactedMessage
    }

    $script:PwshProfileGitHubConfigurationHelpers.IsTransientFailure = {
        param(
            [String]$Message,
            [Nullable[Int32]]$StatusCode
        )

        if ($StatusCode -in 429, 500, 502, 503, 504)
        {
            return $true
        }

        if ([string]::IsNullOrWhiteSpace($Message))
        {
            return $false
        }

        $normalized = $Message.ToLowerInvariant()
        $patterns = @(
            'timeout',
            'timed out',
            'temporar',
            'try again',
            'connection reset',
            'connection refused',
            'eof',
            'tls',
            'handshake',
            'bad gateway',
            'service unavailable',
            'gateway timeout',
            'secondary rate limit',
            'rate limit'
        )

        foreach ($pattern in $patterns)
        {
            if ($normalized -like "*$pattern*")
            {
                return $true
            }
        }

        return $false
    }

    $script:PwshProfileGitHubConfigurationHelpers.InvokeWithRetry = {
        param(
            [ScriptBlock]$Operation,
            [Int]$MaxRetryCount,
            [Int]$InitialRetryDelaySeconds,
            [String]$Activity
        )

        if ($null -eq $Operation)
        {
            throw 'A retry operation script block is required.'
        }

        $attempt = 0
        while ($true)
        {
            try
            {
                return & $Operation
            }
            catch
            {
                $attempt++
                $statusCode = & $script:PwshProfileGitHubConfigurationHelpers.GetExceptionStatusCode $_.Exception
                $message = & $script:PwshProfileGitHubConfigurationHelpers.GetExceptionMessage $_.Exception
                $shouldRetry = & $script:PwshProfileGitHubConfigurationHelpers.IsTransientFailure -Message $message -StatusCode $statusCode

                if (-not $shouldRetry -or $attempt -gt $MaxRetryCount)
                {
                    throw
                }

                $delaySeconds = [Math]::Min(
                    [Math]::Pow(2, $attempt - 1) * $InitialRetryDelaySeconds,
                    $script:PwshProfileGitHubConfigurationHelpers.MaxBackoffSeconds
                )

                Write-Verbose "Transient GitHub failure during '$Activity'. Retrying in $([int][Math]::Ceiling($delaySeconds)) second(s)."
                Start-Sleep -Seconds ([int][Math]::Ceiling($delaySeconds))
            }
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.ResolveAuthContext = {
        param(
            [SecureString]$Token,
            [String]$TokenEnvironmentVariableName,
            [Boolean]$RequireToken
        )

        $plainTextToken = $null
        $source = 'ExistingGhAuth'

        if ($Token)
        {
            $plainTextToken = & $script:PwshProfileGitHubConfigurationHelpers.ConvertSecureStringToPlainText $Token
            $source = 'Parameter'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($TokenEnvironmentVariableName))
        {
            $environmentToken = [Environment]::GetEnvironmentVariable($TokenEnvironmentVariableName, 'Process')

            $supportsPersistentEnvironmentScopes = if ($PSVersionTable.PSVersion.Major -lt 6) { $true } else { $IsWindows }

            if ($supportsPersistentEnvironmentScopes -and [string]::IsNullOrWhiteSpace($environmentToken))
            {
                try
                {
                    $environmentToken = [Environment]::GetEnvironmentVariable($TokenEnvironmentVariableName, 'User')
                }
                catch [System.PlatformNotSupportedException]
                {
                    $environmentToken = $null
                }
            }

            if ($supportsPersistentEnvironmentScopes -and [string]::IsNullOrWhiteSpace($environmentToken))
            {
                try
                {
                    $environmentToken = [Environment]::GetEnvironmentVariable($TokenEnvironmentVariableName, 'Machine')
                }
                catch [System.PlatformNotSupportedException]
                {
                    $environmentToken = $null
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($environmentToken))
            {
                $plainTextToken = $environmentToken
                $source = "Environment:$TokenEnvironmentVariableName"
            }
        }

        if ($RequireToken -and [string]::IsNullOrWhiteSpace($plainTextToken))
        {
            throw "No GitHub token is available. Provide -Token or set the '$TokenEnvironmentVariableName' environment variable."
        }

        return [PSCustomObject]@{
            Token = $plainTextToken
            Source = $source
            TokenEnvironmentVariableName = $TokenEnvironmentVariableName
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.GetGhCommand = {
        return Get-Command -Name 'gh' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1
    }

    $script:PwshProfileGitHubConfigurationHelpers.GetResolvedCommandPath = {
        param(
            [Object]$CommandInfo,
            [String]$FallbackName
        )

        foreach ($propertyName in @('Path', 'Source', 'Definition'))
        {
            $property = $CommandInfo.PSObject.Properties[$propertyName]
            if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value))
            {
                return [string]$property.Value
            }
        }

        return $FallbackName
    }

    $script:PwshProfileGitHubConfigurationHelpers.ResolveTransport = {
        $ghCommand = & $script:PwshProfileGitHubConfigurationHelpers.GetGhCommand

        if ($ghCommand)
        {
            return [PSCustomObject]@{
                Name = 'GhCli'
                Command = $ghCommand
                CommandPath = & $script:PwshProfileGitHubConfigurationHelpers.GetResolvedCommandPath `
                    -CommandInfo $ghCommand `
                    -FallbackName 'gh'
            }
        }

        return [PSCustomObject]@{
            Name = 'RestApi'
            Command = $null
            CommandPath = $null
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.BuildGitHubApiBaseUri = {
        param([String]$GitHubHost)

        if ([string]::IsNullOrWhiteSpace($GitHubHost) -or $GitHubHost -eq 'github.com')
        {
            return 'https://api.github.com'
        }

        return "https://$GitHubHost/api/v3"
    }

    $script:PwshProfileGitHubConfigurationHelpers.ParseRepositorySpecifier = {
        param([String]$Repository)

        if ([string]::IsNullOrWhiteSpace($Repository))
        {
            return $null
        }

        $value = $Repository.Trim()
        $gitHubHost = 'github.com'
        $owner = $null
        $repoName = $null

        if ($value -match '^(?<host>[^/]+)/(?<owner>[^/]+)/(?<repo>[^/]+)$' -and $value -notmatch '^https?://')
        {
            $gitHubHost = $matches['host']
            $owner = $matches['owner']
            $repoName = $matches['repo']
        }
        elseif ($value -match '^(?<owner>[^/]+)/(?<repo>[^/]+)$')
        {
            $owner = $matches['owner']
            $repoName = $matches['repo']
        }
        elseif ($value -match '^(?:ssh://)?git@(?<host>[^:/]+)[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$')
        {
            $gitHubHost = $matches['host']
            $owner = $matches['owner']
            $repoName = $matches['repo']
        }
        elseif ($value -match '^https?://(?<host>[^/]+)/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$')
        {
            $gitHubHost = $matches['host']
            $owner = $matches['owner']
            $repoName = $matches['repo']
        }

        if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repoName))
        {
            throw "Repository '$Repository' must use OWNER/REPO, HOST/OWNER/REPO, or a Git remote URL."
        }

        $repoName = $repoName -replace '\.git$', ''
        $nameWithOwner = "$owner/$repoName"

        return [PSCustomObject]@{
            Host = $gitHubHost
            Owner = $owner
            Repo = $repoName
            NameWithOwner = $nameWithOwner
            GhRepository = if ($gitHubHost -eq 'github.com') { $nameWithOwner } else { "$gitHubHost/$nameWithOwner" }
            ApiBaseUri = & $script:PwshProfileGitHubConfigurationHelpers.BuildGitHubApiBaseUri $gitHubHost
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.ResolveCurrentRepository = {
        $gitCommand = Get-Command -Name 'git' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1

        if (-not $gitCommand)
        {
            return $null
        }

        $gitCommandPath = & $script:PwshProfileGitHubConfigurationHelpers.GetResolvedCommandPath `
            -CommandInfo $gitCommand `
            -FallbackName 'git'

        $output = & $gitCommandPath remote get-url origin 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            return $null
        }

        $remoteUrl = ($output | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($remoteUrl))
        {
            return $null
        }

        try
        {
            return & $script:PwshProfileGitHubConfigurationHelpers.ParseRepositorySpecifier $remoteUrl
        }
        catch
        {
            return $null
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.ResolveRepositoryContext = {
        param([String]$Repository)

        if (-not [string]::IsNullOrWhiteSpace($Repository))
        {
            return & $script:PwshProfileGitHubConfigurationHelpers.ParseRepositorySpecifier $Repository
        }

        $resolvedRepository = & $script:PwshProfileGitHubConfigurationHelpers.ResolveCurrentRepository
        if ($resolvedRepository)
        {
            return $resolvedRepository
        }

        throw 'Unable to determine the GitHub repository from the current directory. Use -Repository OWNER/REPO.'
    }

    $script:PwshProfileGitHubConfigurationHelpers.GetSecretContext = {
        param(
            [String]$Scope,
            [String]$Repository,
            [String]$Environment,
            [String]$Organization,
            [String]$Application
        )

        if ([string]::IsNullOrWhiteSpace($Scope))
        {
            throw 'Secret scope is required.'
        }

        $scope = $Scope

        $effectiveApplication = if ([string]::IsNullOrWhiteSpace($Application))
        {
            switch ($scope)
            {
                'User' { 'codespaces' }
                default { 'actions' }
            }
        }
        else
        {
            $Application.ToLowerInvariant()
        }

        if ($scope -eq 'Environment' -and $effectiveApplication -ne 'actions')
        {
            throw 'Environment secrets support only the actions application.'
        }

        if ($scope -eq 'User' -and $effectiveApplication -ne 'codespaces')
        {
            throw 'User secrets support only the codespaces application.'
        }

        $repositoryContext = $null
        $displayTarget = $null
        $metadataPath = $null
        $publicKeyPath = $null
        $ghTargetArguments = @()

        switch ($scope)
        {
            'Repository'
            {
                $repositoryContext = & $script:PwshProfileGitHubConfigurationHelpers.ResolveRepositoryContext $Repository
                $displayTarget = "repository $($repositoryContext.NameWithOwner)"
                $ghTargetArguments += @('--repo', $repositoryContext.GhRepository)

                $pathPrefix = switch ($effectiveApplication)
                {
                    'codespaces' { "/repos/$($repositoryContext.Owner)/$($repositoryContext.Repo)/codespaces/secrets" }
                    'dependabot' { "/repos/$($repositoryContext.Owner)/$($repositoryContext.Repo)/dependabot/secrets" }
                    default { "/repos/$($repositoryContext.Owner)/$($repositoryContext.Repo)/actions/secrets" }
                }

                $metadataPath = $pathPrefix
                $publicKeyPath = "$pathPrefix/public-key"
            }
            'Environment'
            {
                $repositoryContext = & $script:PwshProfileGitHubConfigurationHelpers.ResolveRepositoryContext $Repository
                $encodedEnvironment = [Uri]::EscapeDataString($Environment)
                $displayTarget = "environment '$Environment' in $($repositoryContext.NameWithOwner)"
                $ghTargetArguments += @('--repo', $repositoryContext.GhRepository, '--env', $Environment)
                $metadataPath = "/repos/$($repositoryContext.Owner)/$($repositoryContext.Repo)/environments/$encodedEnvironment/secrets"
                $publicKeyPath = "$metadataPath/public-key"
            }
            'Organization'
            {
                $displayTarget = "organization $Organization"
                $ghTargetArguments += @('--org', $Organization)

                $pathPrefix = switch ($effectiveApplication)
                {
                    'codespaces' { "/orgs/$Organization/codespaces/secrets" }
                    'dependabot' { "/orgs/$Organization/dependabot/secrets" }
                    default { "/orgs/$Organization/actions/secrets" }
                }

                $metadataPath = $pathPrefix
                $publicKeyPath = "$pathPrefix/public-key"
            }
            'User'
            {
                $displayTarget = 'user codespaces secrets'
                $ghTargetArguments += '--user'
                $metadataPath = '/user/codespaces/secrets'
                $publicKeyPath = '/user/codespaces/secrets/public-key'
            }
        }

        if ($scope -ne 'User' -and -not [string]::IsNullOrWhiteSpace($Application))
        {
            $ghTargetArguments += @('--app', $effectiveApplication)
        }

        return [PSCustomObject]@{
            Scope = $scope
            Application = $effectiveApplication
            RepositoryContext = $repositoryContext
            Organization = $Organization
            Environment = $Environment
            DisplayTarget = $displayTarget
            MetadataCollectionPath = $metadataPath
            MetadataItemPath = $null
            PublicKeyPath = $publicKeyPath
            GhTargetArguments = $ghTargetArguments
            ApiBaseUri = if ($repositoryContext) { $repositoryContext.ApiBaseUri } else { 'https://api.github.com' }
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.GetVariableContext = {
        param(
            [String]$Scope,
            [String]$Repository,
            [String]$Environment,
            [String]$Organization
        )

        if ([string]::IsNullOrWhiteSpace($Scope))
        {
            throw 'Variable scope is required.'
        }

        $scope = $Scope

        $repositoryContext = $null
        $displayTarget = $null
        $collectionPath = $null
        $ghTargetArguments = @()

        switch ($scope)
        {
            'Repository'
            {
                $repositoryContext = & $script:PwshProfileGitHubConfigurationHelpers.ResolveRepositoryContext $Repository
                $displayTarget = "repository $($repositoryContext.NameWithOwner)"
                $ghTargetArguments += @('--repo', $repositoryContext.GhRepository)
                $collectionPath = "/repos/$($repositoryContext.Owner)/$($repositoryContext.Repo)/actions/variables"
            }
            'Environment'
            {
                $repositoryContext = & $script:PwshProfileGitHubConfigurationHelpers.ResolveRepositoryContext $Repository
                $encodedEnvironment = [Uri]::EscapeDataString($Environment)
                $displayTarget = "environment '$Environment' in $($repositoryContext.NameWithOwner)"
                $ghTargetArguments += @('--repo', $repositoryContext.GhRepository, '--env', $Environment)
                $collectionPath = "/repos/$($repositoryContext.Owner)/$($repositoryContext.Repo)/environments/$encodedEnvironment/variables"
            }
            'Organization'
            {
                $displayTarget = "organization $Organization"
                $ghTargetArguments += @('--org', $Organization)
                $collectionPath = "/orgs/$Organization/actions/variables"
            }
        }

        return [PSCustomObject]@{
            Scope = $scope
            RepositoryContext = $repositoryContext
            Organization = $Organization
            Environment = $Environment
            DisplayTarget = $displayTarget
            CollectionPath = $collectionPath
            GhTargetArguments = $ghTargetArguments
            ApiBaseUri = if ($repositoryContext) { $repositoryContext.ApiBaseUri } else { 'https://api.github.com' }
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.GetSingleItemPath = {
        param(
            [String]$CollectionPath,
            [String]$Name
        )

        return "$CollectionPath/$([Uri]::EscapeDataString($Name))"
    }

    $script:PwshProfileGitHubConfigurationHelpers.InvokeGhCommand = {
        param(
            [String[]]$Arguments,
            [PSCustomObject]$AuthContext,
            [Int]$MaxRetryCount,
            [Int]$InitialRetryDelaySeconds,
            [String]$Activity,
            [String[]]$SensitiveValues
        )

        $ghArguments = @($Arguments)
        $ghAuthContext = $AuthContext
        $ghSensitiveValues = @($SensitiveValues)
        $ghCommand = & $script:PwshProfileGitHubConfigurationHelpers.GetGhCommand
        $ghCommandPath = & $script:PwshProfileGitHubConfigurationHelpers.GetResolvedCommandPath `
            -CommandInfo $ghCommand `
            -FallbackName 'gh'

        $operation = {
            $previousGhToken = [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')
            $previousGhPromptDisabled = [Environment]::GetEnvironmentVariable('GH_PROMPT_DISABLED', 'Process')

            if ($ghAuthContext -and -not [string]::IsNullOrWhiteSpace($ghAuthContext.Token))
            {
                [Environment]::SetEnvironmentVariable('GH_TOKEN', $ghAuthContext.Token, 'Process')
            }

            # gh secret delete does not expose a --yes flag, so disable interactive prompts centrally.
            [Environment]::SetEnvironmentVariable('GH_PROMPT_DISABLED', '1', 'Process')

            try
            {
                $output = & $ghCommandPath @ghArguments 2>&1
                $exitCode = $LASTEXITCODE
            }
            finally
            {
                if ($ghAuthContext -and -not [string]::IsNullOrWhiteSpace($ghAuthContext.Token))
                {
                    [Environment]::SetEnvironmentVariable('GH_TOKEN', $previousGhToken, 'Process')
                }

                [Environment]::SetEnvironmentVariable('GH_PROMPT_DISABLED', $previousGhPromptDisabled, 'Process')
            }

            if ($exitCode -ne 0)
            {
                $rawOutputText = ($output | Out-String).Trim()
                $safeOutputText = & $script:PwshProfileGitHubConfigurationHelpers.RedactSensitiveText `
                    -Message (& $script:PwshProfileGitHubConfigurationHelpers.TrimErrorMessage $rawOutputText) `
                    -SensitiveValues (@($ghAuthContext.Token) + @($ghSensitiveValues))

                $exception = [System.InvalidOperationException]::new($safeOutputText)
                if ($rawOutputText -match 'HTTP (\d{3})')
                {
                    $exception.Data['StatusCode'] = [int]$matches[1]
                }

                throw $exception
            }

            return @($output)
        }

        return & $script:PwshProfileGitHubConfigurationHelpers.InvokeWithRetry `
            -Operation $operation `
            -MaxRetryCount $MaxRetryCount `
            -InitialRetryDelaySeconds $InitialRetryDelaySeconds `
            -Activity $Activity
    }

    $script:PwshProfileGitHubConfigurationHelpers.StartGhCommandWithStandardInput = {
        param(
            [String[]]$Arguments,
            [String]$StandardInputText
        )

        $ghCommand = & $script:PwshProfileGitHubConfigurationHelpers.GetGhCommand
        $ghCommandPath = & $script:PwshProfileGitHubConfigurationHelpers.GetResolvedCommandPath `
            -CommandInfo $ghCommand `
            -FallbackName 'gh'

        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $standardInputPath = $null
            $standardOutputPath = $null
            $standardErrorPath = $null

            try
            {
                $standardInputPath = [System.IO.Path]::GetTempFileName()
                $standardOutputPath = [System.IO.Path]::GetTempFileName()
                $standardErrorPath = [System.IO.Path]::GetTempFileName()

                [System.IO.File]::WriteAllText($standardInputPath, $StandardInputText, [System.Text.UTF8Encoding]::new($false))

                $escapedArguments = foreach ($argument in @($Arguments))
                {
                    & $script:PwshProfileGitHubConfigurationHelpers.QuoteNativeProcessArgument `
                        -Argument ([string]$argument)
                }

                $process = Start-Process `
                    -FilePath $ghCommandPath `
                    -ArgumentList ($escapedArguments -join ' ') `
                    -Wait `
                    -PassThru `
                    -NoNewWindow `
                    -RedirectStandardInput $standardInputPath `
                    -RedirectStandardOutput $standardOutputPath `
                    -RedirectStandardError $standardErrorPath

                return [PSCustomObject]@{
                    ExitCode = $process.ExitCode
                    StandardOutput = [System.IO.File]::ReadAllText($standardOutputPath)
                    StandardError = [System.IO.File]::ReadAllText($standardErrorPath)
                }
            }
            finally
            {
                foreach ($tempPath in @($standardInputPath, $standardOutputPath, $standardErrorPath))
                {
                    if (-not [string]::IsNullOrWhiteSpace($tempPath) -and (Test-Path -LiteralPath $tempPath))
                    {
                        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        $process = [System.Diagnostics.Process]::new()
        try
        {
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $ghCommandPath
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true

            foreach ($argument in @($Arguments))
            {
                $null = $startInfo.ArgumentList.Add([string]$argument)
            }

            $process.StartInfo = $startInfo
            $null = $process.Start()

            if ($null -ne $StandardInputText)
            {
                $process.StandardInput.Write($StandardInputText)
            }

            $process.StandardInput.Close()

            $standardOutput = $process.StandardOutput.ReadToEnd()
            $standardError = $process.StandardError.ReadToEnd()
            $process.WaitForExit()

            return [PSCustomObject]@{
                ExitCode = $process.ExitCode
                StandardOutput = $standardOutput
                StandardError = $standardError
            }
        }
        finally
        {
            if ($process)
            {
                $process.Dispose()
            }
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.QuoteNativeProcessArgument = {
        param([AllowNull()][String]$Argument)

        if ($null -eq $Argument -or $Argument.Length -eq 0)
        {
            return '""'
        }

        if ($Argument -notmatch '[\s"]')
        {
            return $Argument
        }

        $builder = [System.Text.StringBuilder]::new()
        $null = $builder.Append('"')
        $backslashCount = 0

        foreach ($character in $Argument.ToCharArray())
        {
            if ($character -eq '\')
            {
                $backslashCount++
                continue
            }

            if ($character -eq '"')
            {
                $null = $builder.Append(('\' * (($backslashCount * 2) + 1)))
                $null = $builder.Append('"')
                $backslashCount = 0
                continue
            }

            if ($backslashCount -gt 0)
            {
                $null = $builder.Append(('\' * $backslashCount))
                $backslashCount = 0
            }

            $null = $builder.Append($character)
        }

        if ($backslashCount -gt 0)
        {
            $null = $builder.Append(('\' * ($backslashCount * 2)))
        }

        $null = $builder.Append('"')
        return $builder.ToString()
    }

    $script:PwshProfileGitHubConfigurationHelpers.InvokeGhCommandWithStandardInput = {
        param(
            [String[]]$Arguments,
            [String]$StandardInputText,
            [PSCustomObject]$AuthContext,
            [Int]$MaxRetryCount,
            [Int]$InitialRetryDelaySeconds,
            [String]$Activity,
            [String[]]$SensitiveValues
        )

        $ghArguments = @($Arguments)
        $ghStandardInputText = $StandardInputText
        $ghAuthContext = $AuthContext
        $ghSensitiveValues = @($SensitiveValues)

        $operation = {
            $previousGhToken = [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')
            $previousGhPromptDisabled = [Environment]::GetEnvironmentVariable('GH_PROMPT_DISABLED', 'Process')

            if ($ghAuthContext -and -not [string]::IsNullOrWhiteSpace($ghAuthContext.Token))
            {
                [Environment]::SetEnvironmentVariable('GH_TOKEN', $ghAuthContext.Token, 'Process')
            }

            # gh secret delete does not expose a --yes flag, so disable interactive prompts centrally.
            [Environment]::SetEnvironmentVariable('GH_PROMPT_DISABLED', '1', 'Process')

            try
            {
                $result = & $script:PwshProfileGitHubConfigurationHelpers.StartGhCommandWithStandardInput `
                    -Arguments $ghArguments `
                    -StandardInputText $ghStandardInputText
            }
            finally
            {
                if ($ghAuthContext -and -not [string]::IsNullOrWhiteSpace($ghAuthContext.Token))
                {
                    [Environment]::SetEnvironmentVariable('GH_TOKEN', $previousGhToken, 'Process')
                }

                [Environment]::SetEnvironmentVariable('GH_PROMPT_DISABLED', $previousGhPromptDisabled, 'Process')
            }

            if ($result.ExitCode -ne 0)
            {
                $rawOutputText = @($result.StandardError, $result.StandardOutput) -join [Environment]::NewLine
                $safeOutputText = & $script:PwshProfileGitHubConfigurationHelpers.RedactSensitiveText `
                    -Message (& $script:PwshProfileGitHubConfigurationHelpers.TrimErrorMessage $rawOutputText) `
                    -SensitiveValues (@($ghAuthContext.Token) + @($ghStandardInputText) + @($ghSensitiveValues))

                $exception = [System.InvalidOperationException]::new($safeOutputText)
                if ($rawOutputText -match 'HTTP (\d{3})')
                {
                    $exception.Data['StatusCode'] = [int]$matches[1]
                }

                throw $exception
            }

            if ([string]::IsNullOrWhiteSpace($result.StandardOutput))
            {
                return @()
            }

            return @($result.StandardOutput)
        }

        return & $script:PwshProfileGitHubConfigurationHelpers.InvokeWithRetry `
            -Operation $operation `
            -MaxRetryCount $MaxRetryCount `
            -InitialRetryDelaySeconds $InitialRetryDelaySeconds `
            -Activity $Activity
    }

    $script:PwshProfileGitHubConfigurationHelpers.InvokeGitHubRequest = {
        param(
            [String]$Method,
            [String]$BaseUri,
            [String]$Path,
            [PSCustomObject]$Transport,
            [PSCustomObject]$AuthContext,
            [Object]$Body,
            [Int]$MaxRetryCount,
            [Int]$InitialRetryDelaySeconds,
            [String]$Activity,
            [String[]]$SensitiveValues
        )

        if ($Transport.Name -eq 'GhCli')
        {
            $arguments = @(
                'api',
                '--method', $Method.ToUpperInvariant(),
                '-H', 'Accept: application/vnd.github+json'
            )

            $uri = [Uri]$BaseUri
            $ghHost = if ($uri.Host -eq 'api.github.com') { 'github.com' } else { $uri.Host }
            if ($ghHost -ne 'github.com')
            {
                $arguments += @('--hostname', $ghHost)
            }

            $tempFile = $null
            try
            {
                if ($null -ne $Body)
                {
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    $jsonBody = $Body | ConvertTo-Json -Depth 10 -Compress
                    [System.IO.File]::WriteAllText($tempFile, $jsonBody, [System.Text.UTF8Encoding]::new($false))
                    $arguments += @('--input', $tempFile)
                }
                $arguments += $Path

                $output = & $script:PwshProfileGitHubConfigurationHelpers.InvokeGhCommand `
                    -Arguments $arguments `
                    -AuthContext $AuthContext `
                    -MaxRetryCount $MaxRetryCount `
                    -InitialRetryDelaySeconds $InitialRetryDelaySeconds `
                    -Activity $Activity `
                    -SensitiveValues $SensitiveValues

                $text = ($output | Out-String).Trim()
                if ([string]::IsNullOrWhiteSpace($text))
                {
                    return $null
                }

                return $text | ConvertFrom-Json
            }
            finally
            {
                if ($tempFile -and (Test-Path -LiteralPath $tempFile))
                {
                    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
        }

        $tokenEnvironmentVariableName = if (
            $AuthContext -and
            -not [string]::IsNullOrWhiteSpace($AuthContext.TokenEnvironmentVariableName)
        )
        {
            $AuthContext.TokenEnvironmentVariableName
        }
        else
        {
            'GH_TOKEN'
        }

        if ($null -eq $AuthContext -or [string]::IsNullOrWhiteSpace($AuthContext.Token))
        {
            throw "No GitHub token is available for REST API access. Provide -Token or set the '$tokenEnvironmentVariableName' environment variable."
        }

        $headers = @{
            Accept = 'application/vnd.github+json'
            Authorization = "Bearer $($AuthContext.Token)"
        }

        $operation = {
            try
            {
                $invokeRestParams = @{
                    Method = $Method
                    Uri = "$BaseUri$Path"
                    Headers = $headers
                    ErrorAction = 'Stop'
                }

                if ($null -ne $Body)
                {
                    $invokeRestParams['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
                    $invokeRestParams['ContentType'] = 'application/json'
                }

                return Invoke-RestMethod @invokeRestParams
            }
            catch
            {
                $statusCode = & $script:PwshProfileGitHubConfigurationHelpers.GetExceptionStatusCode $_.Exception
                $safeMessage = & $script:PwshProfileGitHubConfigurationHelpers.RedactSensitiveText `
                    -Message (& $script:PwshProfileGitHubConfigurationHelpers.TrimErrorMessage `
                        (& $script:PwshProfileGitHubConfigurationHelpers.GetExceptionMessage $_.Exception)) `
                    -SensitiveValues (@($AuthContext.Token) + @($SensitiveValues))

                $sanitizedException = [System.InvalidOperationException]::new($safeMessage)
                if ($null -ne $statusCode)
                {
                    $sanitizedException.Data['StatusCode'] = $statusCode
                }

                throw $sanitizedException
            }
        }

        return & $script:PwshProfileGitHubConfigurationHelpers.InvokeWithRetry `
            -Operation $operation `
            -MaxRetryCount $MaxRetryCount `
            -InitialRetryDelaySeconds $InitialRetryDelaySeconds `
            -Activity $Activity
    }

    $script:PwshProfileGitHubConfigurationHelpers.TryGetGitHubResource = {
        param(
            [String]$Path,
            [String]$BaseUri,
            [PSCustomObject]$Transport,
            [PSCustomObject]$AuthContext,
            [Int]$MaxRetryCount,
            [Int]$InitialRetryDelaySeconds,
            [String]$Activity
        )

        try
        {
            return [PSCustomObject]@{
                Found = $true
                Resource = & $script:PwshProfileGitHubConfigurationHelpers.InvokeGitHubRequest `
                    -Method 'GET' `
                    -BaseUri $BaseUri `
                    -Path $Path `
                    -Transport $Transport `
                    -AuthContext $AuthContext `
                    -Body $null `
                    -MaxRetryCount $MaxRetryCount `
                    -InitialRetryDelaySeconds $InitialRetryDelaySeconds `
                    -Activity $Activity
            }
        }
        catch
        {
            $statusCode = & $script:PwshProfileGitHubConfigurationHelpers.GetExceptionStatusCode $_.Exception
            $message = & $script:PwshProfileGitHubConfigurationHelpers.GetExceptionMessage $_.Exception
            if ($statusCode -eq 404 -or $message -match '\bnot found\b')
            {
                return [PSCustomObject]@{
                    Found = $false
                    Resource = $null
                }
            }

            throw
        }
    }

    $script:PwshProfileGitHubConfigurationHelpers.ResolveSelectedRepositoryIds = {
        param(
            [String[]]$Repositories,
            [String]$Organization,
            [PSCustomObject]$Transport,
            [PSCustomObject]$AuthContext,
            [Int]$MaxRetryCount,
            [Int]$InitialRetryDelaySeconds
        )

        $repositoryIds = New-Object System.Collections.Generic.List[Int64]

        foreach ($repository in @($Repositories | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
        {
            $repositoryValue = $repository.Trim()

            if ($repositoryValue -notmatch '/')
            {
                if ([string]::IsNullOrWhiteSpace($Organization))
                {
                    throw "Selected repository '$repositoryValue' must use OWNER/REPO format."
                }

                $repositoryValue = "$Organization/$repositoryValue"
            }

            $repositoryContext = & $script:PwshProfileGitHubConfigurationHelpers.ParseRepositorySpecifier $repositoryValue
            $lookup = & $script:PwshProfileGitHubConfigurationHelpers.InvokeGitHubRequest `
                -Method 'GET' `
                -BaseUri $repositoryContext.ApiBaseUri `
                -Path "/repos/$($repositoryContext.Owner)/$($repositoryContext.Repo)" `
                -Transport $Transport `
                -AuthContext $AuthContext `
                -Body $null `
                -MaxRetryCount $MaxRetryCount `
                -InitialRetryDelaySeconds $InitialRetryDelaySeconds `
                -Activity "Resolve repository id for $repositoryValue"

            $repositoryIds.Add([int64]$lookup.id) | Out-Null
        }

        return @($repositoryIds.ToArray())
    }

    $script:PwshProfileGitHubConfigurationHelpers.GetFriendlyErrorMessage = {
        param(
            [String]$Operation,
            [String]$Name,
            [String]$Target,
            [System.Exception]$Exception
        )

        $statusCode = & $script:PwshProfileGitHubConfigurationHelpers.GetExceptionStatusCode $Exception
        $message = & $script:PwshProfileGitHubConfigurationHelpers.TrimErrorMessage `
        (& $script:PwshProfileGitHubConfigurationHelpers.GetExceptionMessage $Exception)

        if ($statusCode -eq 401 -or $message -match 'authentication|token|unauthorized')
        {
            return "Failed to $Operation '$Name' for ${Target}: authentication failed."
        }

        if ($statusCode -eq 403 -or $message -match 'forbidden|resource not accessible|admin rights')
        {
            return "Failed to $Operation '$Name' for ${Target}: insufficient permissions."
        }

        if ($statusCode -eq 404 -or $message -match '\bnot found\b')
        {
            return "Failed to $Operation '$Name' for ${Target}: resource not found."
        }

        if ($statusCode -eq 422)
        {
            return "Failed to $Operation '$Name' for ${Target}: validation failed. $message"
        }

        return "Failed to $Operation '$Name' for ${Target}: $message"
    }
}
