function ConvertFrom-Base64
{
    <#
    .SYNOPSIS
        Decodes a Base64-encoded string to its original text or file content.

    .DESCRIPTION
        Decodes Base64-encoded input back to plain text or writes binary content to a file.
        Supports both standard and URL-safe Base64 decoding. Can accept input from pipeline
        or parameters.

        Cross-platform compatible with PowerShell 5.1+ and PowerShell Core.

        Aliases:
        The 'base64-decode' alias is created only if it doesn't already exist in the current environment.

    .PARAMETER InputObject
        The Base64-encoded string to decode. Can be provided via pipeline.

    .PARAMETER OutputPath
        Optional path to write decoded binary content to a file. If not specified,
        the decoded content is returned as a UTF-8 string.

    .PARAMETER UrlSafe
        Indicates that the input uses URL-safe Base64 encoding (- instead of +, _ instead of /).

    .EXAMPLE
        PS > ConvertFrom-Base64 -InputObject 'SGVsbG8gV29ybGQ='
        Hello World

        Decodes a Base64 string to plain text.

    .EXAMPLE
        PS > 'SGVsbG8gV29ybGQ=' | ConvertFrom-Base64
        Hello World

        Decodes a Base64 string from pipeline input.

    .EXAMPLE
        PS > ConvertFrom-Base64 -InputObject 'SGVsbG8gV29ybGQ' -UrlSafe
        Hello World

        Decodes a URL-safe Base64 string (no padding).

    .EXAMPLE
        PS > ConvertFrom-Base64 -InputObject 'VGhpcyBpcyBhIHRlc3QgZmlsZQ==' -OutputPath './decoded.txt'

        Decodes Base64 content and writes it to a file.

    .EXAMPLE
        PS > Get-Content './encoded.txt' | ConvertFrom-Base64
        Decoded content here

        Decodes Base64 text from stdin/pipeline.

    .EXAMPLE
        PS > $token = ConvertTo-Base64 -InputObject 'client-id:client-secret'
        PS > ConvertFrom-Base64 -InputObject $token
        client-id:client-secret

        Quickly inspects what was placed inside an HTTP Basic authorization header.

    .EXAMPLE
        PS > $dataUri = Get-Content './image.txt'
        PS > $base64 = $dataUri -replace '^data:image/[^;]+;base64,', ''
        PS > ConvertFrom-Base64 -InputObject $base64 -OutputPath './restored.png'

        Strips the prefix from a data URI and writes the decoded image back to disk.

    .OUTPUTS
        System.String
        The decoded text (when OutputPath is not specified).

    .NOTES
        For URL-safe decoding, the input follows RFC 4648 Section 5.
        When writing to a file, the function handles binary data correctly.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ToString')]
    [OutputType([String])]
    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [String]$InputObject,

        [Parameter(
            ParameterSetName = 'ToFile'
        )]
        [String]$OutputPath,

        [Parameter()]
        [Switch]$UrlSafe
    )

    begin
    {
        Write-Verbose 'Starting Base64 decoding'
        $results = [System.Collections.ArrayList]::new()
    }

    process
    {
        try
        {
            # Prepare the Base64 string
            $base64String = $InputObject

            # Convert from URL-safe encoding if requested
            if ($UrlSafe)
            {
                $base64String = $base64String.Replace('-', '+').Replace('_', '/')
                # Add padding if needed
                $remainder = $base64String.Length % 4
                if ($remainder -gt 0)
                {
                    $base64String += '=' * (4 - $remainder)
                }
                Write-Verbose 'Converted from URL-safe encoding'
            }

            # Decode from Base64
            $bytes = [System.Convert]::FromBase64String($base64String)

            if ($PSCmdlet.ParameterSetName -eq 'ToFile')
            {
                # Write binary content to file
                if (-not $OutputPath)
                {
                    throw 'OutputPath parameter is required for file output'
                }

                $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
                Write-Verbose "Writing decoded content to: $resolvedPath"

                # Ensure directory exists
                $directory = [System.IO.Path]::GetDirectoryName($resolvedPath)
                if ($directory -and -not (Test-Path -Path $directory))
                {
                    $null = New-Item -Path $directory -ItemType Directory -Force
                }

                [System.IO.File]::WriteAllBytes($resolvedPath, $bytes)
                Write-Verbose "Successfully wrote $($bytes.Length) bytes to file"
            }
            else
            {
                # Convert bytes to UTF-8 string
                $decodedText = [System.Text.Encoding]::UTF8.GetString($bytes)
                $null = $results.Add($decodedText)
            }
        }
        catch [System.FormatException]
        {
            Write-Error "Invalid Base64 string: $($_.Exception.Message)"
            throw
        }
        catch
        {
            Write-Error "Failed to decode from Base64: $($_.Exception.Message)"
            throw
        }
    }

    end
    {
        if ($PSCmdlet.ParameterSetName -eq 'ToString')
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
        }
        Write-Verbose 'Base64 decoding completed'
    }
}

# Create 'base64-decode' alias only if it doesn't already exist
if (-not (Get-Command -Name 'base64-decode' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'base64-decode' alias for ConvertFrom-Base64"
        Set-Alias -Name 'base64-decode' -Value 'ConvertFrom-Base64' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "ConvertFrom-Base64: Could not create 'base64-decode' alias: $($_.Exception.Message)"
    }
}
