function Get-FileEncoding
{
    <#
    .SYNOPSIS
        Detects text file encoding using BOM and content sampling.

    .DESCRIPTION
        Detects a file's text encoding by first checking known BOM signatures,
        then sampling file bytes when no BOM is present.

        Detection strategy:
        1. Check BOM for UTF-32 LE/BE, UTF-8 BOM, UTF-16 LE/BE.
        2. If no BOM is present, validate UTF-8 on an 8KB sample.
        3. If UTF-8 validation fails, check whether content is pure ASCII.
        4. Fallback to UTF-8 without BOM.

        Resolution behavior:
        - Files with recognized BOMs return the corresponding encoding.
        - Files without a BOM use heuristic detection from sampled bytes.
        - Empty files return UTF-8 without BOM.
        - Any read/detection error returns UTF-8 without BOM and writes a verbose message.

        This helper is used by content-modifying functions that need
        consistent read/write encoding behavior across PowerShell editions,
        including Convert-LineEndings, Replace-StringInFile, and ConvertTo-Markdown.

    .PARAMETER FilePath
        Path to the file to inspect.

        The path can be relative or absolute and must point to a readable file.
        Wildcard matching is not supported.

    .EXAMPLE
        PS > Get-FileEncoding -FilePath './notes.txt'

        Returns the detected encoding object for notes.txt.

    .EXAMPLE
        PS > $enc = Get-FileEncoding -FilePath './data.csv'
        PS > $enc.EncodingName
        Unicode (UTF-8)

        Detects file encoding and shows the friendly encoding name.

    .EXAMPLE
        PS > Get-ChildItem *.txt | ForEach-Object {
             [PSCustomObject]@{
               File = $_.Name
               Encoding = (Get-FileEncoding -FilePath $_.FullName).EncodingName
             }
           }

        Reports detected encodings for multiple text files.

    .EXAMPLE
        PS > $enc = Get-FileEncoding -FilePath './legacy.ini'
        PS > [System.IO.File]::ReadAllText('./legacy.ini', $enc)

        Reads a file using its detected encoding to avoid character corruption.

    .EXAMPLE
        PS > Set-Content -Path './empty.txt' -Value '' -NoNewline
        PS > (Get-FileEncoding -FilePath './empty.txt').WebName
        utf-8

        Shows that empty files default to UTF-8 without BOM.

    .EXAMPLE
        PS > Get-FileEncoding -FilePath './missing.txt' -Verbose

        If the file cannot be read, writes a verbose diagnostic message and
        returns UTF-8 without BOM as a safe fallback.

    .OUTPUTS
        System.Text.Encoding
            Returns the detected encoding.

            For unreadable files or detection failures, returns UTF-8 without BOM.

    .NOTES
        This is a pragmatic detector intended for common text-processing workflows.
        When no BOM is present, detection is heuristic and not a full charset classifier.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Get-FileEncoding.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Get-FileEncoding.ps1

    .LINK
        Get-EncodingFromName
    #>
    [CmdletBinding()]
    [OutputType([System.Text.Encoding])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$FilePath
    )

    try
    {
        $stream = [System.IO.File]::OpenRead($FilePath)
        try
        {
            if ($stream.Length -eq 0)
            {
                return New-Object System.Text.UTF8Encoding($false)
            }

            $bomBuffer = New-Object byte[] 4
            $bomBytesRead = $stream.Read($bomBuffer, 0, 4)

            if ($bomBytesRead -ge 4 -and $bomBuffer[0] -eq 0xFF -and $bomBuffer[1] -eq 0xFE -and $bomBuffer[2] -eq 0x00 -and $bomBuffer[3] -eq 0x00)
            {
                return [System.Text.Encoding]::UTF32
            }
            if ($bomBytesRead -ge 4 -and $bomBuffer[0] -eq 0x00 -and $bomBuffer[1] -eq 0x00 -and $bomBuffer[2] -eq 0xFE -and $bomBuffer[3] -eq 0xFF)
            {
                return [System.Text.Encoding]::GetEncoding('utf-32BE')
            }
            if ($bomBytesRead -ge 3 -and $bomBuffer[0] -eq 0xEF -and $bomBuffer[1] -eq 0xBB -and $bomBuffer[2] -eq 0xBF)
            {
                return New-Object System.Text.UTF8Encoding($true)
            }
            if ($bomBytesRead -ge 2 -and $bomBuffer[0] -eq 0xFF -and $bomBuffer[1] -eq 0xFE)
            {
                return [System.Text.Encoding]::Unicode
            }
            if ($bomBytesRead -ge 2 -and $bomBuffer[0] -eq 0xFE -and $bomBuffer[1] -eq 0xFF)
            {
                return [System.Text.Encoding]::BigEndianUnicode
            }

            $stream.Position = 0
            $sampleSize = [Math]::Min($stream.Length, 8192)
            $sampleBuffer = New-Object byte[] $sampleSize
            $sampleBytesRead = $stream.Read($sampleBuffer, 0, $sampleSize)

            if ($sampleBytesRead -eq 0)
            {
                return New-Object System.Text.UTF8Encoding($false)
            }

            try
            {
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)
                $decoded = $utf8NoBom.GetString($sampleBuffer, 0, $sampleBytesRead)
                $reencoded = $utf8NoBom.GetBytes($decoded)

                if ($sampleBytesRead -eq $reencoded.Length)
                {
                    $bytesMatch = $true
                    for ($i = 0; $i -lt $sampleBytesRead; $i++)
                    {
                        if ($sampleBuffer[$i] -ne $reencoded[$i])
                        {
                            $bytesMatch = $false
                            break
                        }
                    }

                    if ($bytesMatch)
                    {
                        return $utf8NoBom
                    }
                }
            }
            catch
            {
                Write-Verbose "File '$FilePath' sample is not valid UTF-8"
            }

            $isAscii = $true
            for ($i = 0; $i -lt $sampleBytesRead; $i++)
            {
                if ($sampleBuffer[$i] -gt 127)
                {
                    $isAscii = $false
                    break
                }
            }

            if ($isAscii)
            {
                return [System.Text.Encoding]::ASCII
            }

            return New-Object System.Text.UTF8Encoding($false)
        }
        finally
        {
            $stream.Close()
        }
    }
    catch
    {
        Write-Verbose "Error detecting encoding for '$FilePath': $($_.Exception.Message)"
        return New-Object System.Text.UTF8Encoding($false)
    }
}
