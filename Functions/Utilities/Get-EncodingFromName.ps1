function Get-EncodingFromName
{
    <#
    .SYNOPSIS
        Resolves a profile encoding name to a .NET encoding instance.

    .DESCRIPTION
        Converts the standardized encoding names used throughout this profile into
        [System.Text.Encoding] instances for consistent file processing behavior.

        This helper is primarily used by content-modifying utilities such as
        Convert-LineEndings, Replace-StringInFile, and ConvertTo-Markdown.

        Resolution behavior:
        - Null, empty, or whitespace input returns $null.
        - 'Auto' returns $null to signal "preserve/detect source encoding" mode.
        - Supported names return a concrete System.Text.Encoding instance.
        - Unsupported names produce a non-terminating error and return $null.

        Encoding names are matched case-insensitively.

    .PARAMETER EncodingName
        The encoding name to resolve. Matching is case-insensitive.

        When omitted, empty, whitespace, or set to 'Auto', the function returns $null.
        Caller functions interpret $null as "preserve/detect existing encoding."

        Supported values:
        - Auto: Preserve/detect source encoding (returns $null)
        - UTF8: UTF-8 without BOM
        - UTF8BOM: UTF-8 with BOM
        - UTF16LE: UTF-16 Little Endian with BOM
        - UTF16BE: UTF-16 Big Endian with BOM
        - UTF32: UTF-32 Little Endian with BOM
        - UTF32BE: UTF-32 Big Endian with BOM
        - ASCII: 7-bit ASCII encoding
        - ANSI: System default ANSI encoding (code page dependent)

    .EXAMPLE
        PS > Get-EncodingFromName -EncodingName 'UTF8'

        Resolves UTF-8 without BOM and returns a System.Text.UTF8Encoding instance.

    .EXAMPLE
        PS > (Get-EncodingFromName -EncodingName 'UTF8BOM').GetPreamble().Length
        3

        Confirms that UTF8BOM includes the UTF-8 BOM preamble.

    .EXAMPLE
        PS > Get-EncodingFromName -EncodingName 'Auto'

        Returns $null so caller functions can preserve/detect the existing file encoding.

    .EXAMPLE
        PS > Get-EncodingFromName -EncodingName $null

        Returns $null when no encoding is specified.

    .EXAMPLE
        PS > $enc = Get-EncodingFromName -EncodingName 'UTF16LE'
        PS > [System.IO.File]::WriteAllText('./out.txt', 'hello', $enc)

        Resolves UTF-16 LE encoding and uses it to write a file.

    .EXAMPLE
        PS > Get-EncodingFromName -EncodingName 'INVALID'

        Writes an error indicating the encoding name is unsupported and returns $null.

    .OUTPUTS
        System.Text.Encoding
            Returns an encoding instance for supported names.

        System.Object
            Returns $null when EncodingName is null, empty, whitespace, Auto, or unsupported.

    .NOTES
        This function intentionally returns $null for Auto/empty values so callers can decide
        whether to preserve source encoding or detect encoding from file content.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Get-EncodingFromName.ps1

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Get-EncodingFromName.ps1

    .LINK
        Get-FileEncoding
    #>
    [CmdletBinding()]
    [OutputType([System.Text.Encoding])]
    param(
        [Parameter()]
        [AllowNull()]
        [String]$EncodingName
    )

    if ([String]::IsNullOrWhiteSpace($EncodingName))
    {
        return $null
    }

    try
    {
        switch ($EncodingName.ToUpperInvariant())
        {
            'AUTO' { return $null }
            'UTF8' { return New-Object System.Text.UTF8Encoding($false) }
            'UTF8BOM' { return New-Object System.Text.UTF8Encoding($true) }
            'UTF16LE' { return [System.Text.Encoding]::Unicode }
            'UTF16BE' { return [System.Text.Encoding]::BigEndianUnicode }
            'UTF32' { return [System.Text.Encoding]::UTF32 }
            'UTF32BE' { return [System.Text.Encoding]::GetEncoding('utf-32BE') }
            'ASCII' { return [System.Text.Encoding]::ASCII }
            'ANSI' { return [System.Text.Encoding]::Default }
            default
            {
                throw "Unsupported encoding: $EncodingName"
            }
        }
    }
    catch
    {
        # Keep this error non-terminating even when caller preference is Stop.
        Write-Error "Failed to create encoding '$EncodingName': $($_.Exception.Message)" -ErrorAction Continue
        return $null
    }
}
