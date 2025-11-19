function ConvertTo-Base64
{
    <#
    .SYNOPSIS
        Converts a string or file content to Base64 encoding.

    .DESCRIPTION
        Encodes input text or file content to Base64 format. Supports both standard
        and URL-safe Base64 encoding. Can accept input from pipeline, parameters,
        or read from files.

        Cross-platform compatible with PowerShell 5.1+ and PowerShell Core.

        Aliases:
        The 'base64-encode' alias is created only if it doesn't already exist in the current environment.

    .PARAMETER InputObject
        The string to encode. Can be provided via pipeline.

    .PARAMETER Path
        Path to a file whose content should be encoded.

    .PARAMETER UrlSafe
        Use URL-safe Base64 encoding (replaces + with -, / with _, and removes padding =).

    .EXAMPLE
        PS > ConvertTo-Base64 -InputObject 'Hello World'
        SGVsbG8gV29ybGQ=

        Encodes a simple string to Base64.

    .EXAMPLE
        PS > 'Hello World' | ConvertTo-Base64
        SGVsbG8gV29ybGQ=

        Encodes a string from pipeline input.

    .EXAMPLE
        PS > ConvertTo-Base64 -InputObject 'Hello World' -UrlSafe
        SGVsbG8gV29ybGQ

        Encodes a string using URL-safe Base64 (no padding).

    .EXAMPLE
        PS > ConvertTo-Base64 -Path './document.txt'
        VGhpcyBpcyBhIHRlc3QgZmlsZQ==

        Encodes the content of a file to Base64.

    .EXAMPLE
        PS > Get-Content './data.txt' | ConvertTo-Base64
        VGVzdCBkYXRh

        Encodes text from stdin/pipeline.

    .OUTPUTS
        System.String
        The Base64-encoded string.

    .NOTES
        For URL-safe encoding, the output follows RFC 4648 Section 5.
    #>
    [CmdletBinding(DefaultParameterSetName = 'String')]
    [OutputType([String])]
    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ParameterSetName = 'String',
            Position = 0
        )]
        [AllowEmptyString()]
        [String]$InputObject,

        [Parameter(
            Mandatory,
            ParameterSetName = 'File'
        )]
        [ValidateScript({
                if (-not (Test-Path -Path $_ -PathType Leaf))
                {
                    throw "File not found: $_"
                }
                $true
            })]
        [String]$Path,

        [Parameter()]
        [Switch]$UrlSafe
    )

    begin
    {
        Write-Verbose 'Starting Base64 encoding'
        $results = [System.Collections.ArrayList]::new()
    }

    process
    {
        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'File')
            {
                # Resolve path to absolute path
                $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
                Write-Verbose "Reading file: $resolvedPath"

                # Read file as bytes
                $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
                $base64 = [System.Convert]::ToBase64String($bytes)
            }
            else
            {
                # Encode string input
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputObject)
                $base64 = [System.Convert]::ToBase64String($bytes)
            }

            # Apply URL-safe encoding if requested
            if ($UrlSafe)
            {
                $base64 = $base64.Replace('+', '-').Replace('/', '_').TrimEnd('=')
                Write-Verbose 'Applied URL-safe encoding'
            }

            # Accumulate results for pipeline input
            $null = $results.Add($base64)
        }
        catch
        {
            Write-Error "Failed to encode to Base64: $($_.Exception.Message)"
            throw
        }
    }

    end
    {
        # For single result, return as-is; for multiple, join with newlines
        if ($results.Count -eq 1)
        {
            Write-Output $results[0]
        }
        elseif ($results.Count -gt 1)
        {
            Write-Output ($results -join [Environment]::NewLine)
        }
        Write-Verbose 'Base64 encoding completed'
    }
}

# Create 'base64-encode' alias if it doesn't already exist
if (-not (Get-Alias -Name 'base64-encode' -ErrorAction SilentlyContinue))
{
    try
    {
        Set-Alias -Name 'base64-encode' -Value 'ConvertTo-Base64' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "ConvertTo-Base64: Could not create 'base64-encode' alias: $($_.Exception.Message)"
    }
}
