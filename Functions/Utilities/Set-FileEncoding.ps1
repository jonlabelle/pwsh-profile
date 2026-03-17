function Set-FileEncoding
{
    <#
    .SYNOPSIS
        Converts one or more text files to a specified encoding.

    .DESCRIPTION
        Rewrites text files using the requested target encoding while preserving the
        current text content.

        By default, the function first detects the current file encoding and skips
        files that already match the requested encoding. Use -Force to rewrite files
        even when the detected source encoding already matches the target encoding.

        Binary files are skipped to reduce the risk of corruption.

        Dependencies:
        - Get-EncodingFromName: Resolves profile encoding names to .NET encoding instances.
        - Get-FileEncoding: Detects the current text encoding before conversion.

        Both dependencies are automatically loaded when needed.

    .PARAMETER Path
        One or more file paths to process. Supports wildcards and pipeline input.

    .PARAMETER LiteralPath
        One or more literal file paths to process. Wildcards are treated as literal characters.

    .PARAMETER Encoding
        The target encoding to apply.

        Valid values:
        - UTF8: UTF-8 without BOM
        - UTF8BOM: UTF-8 with BOM
        - UTF16LE: UTF-16 Little Endian with BOM
        - UTF16BE: UTF-16 Big Endian with BOM
        - UTF32: UTF-32 Little Endian with BOM
        - UTF32BE: UTF-32 Big Endian with BOM
        - ASCII: 7-bit ASCII encoding
        - ANSI: System default ANSI encoding (code page dependent)

    .PARAMETER Force
        Rewrites the file even when the detected source encoding already matches the
        requested target encoding.

        When the target file is read-only, Force also temporarily clears the read-only
        attribute so the rewrite can proceed and then restores the original attributes.

    .PARAMETER PassThru
        Returns a summary object for each processed or skipped text file.

    .EXAMPLE
        PS > Set-FileEncoding -Path './notes.txt' -Encoding UTF8BOM

        Rewrites notes.txt as UTF-8 with BOM if it is not already in that encoding.

    .EXAMPLE
        PS > Get-ChildItem '*.ps1' | Set-FileEncoding -Encoding UTF8 -PassThru

        Converts matching PowerShell files to UTF-8 without BOM and returns a summary
        object for each file.

    .EXAMPLE
        PS > Set-FileEncoding -LiteralPath './file[1].txt' -Encoding UTF16LE

        Converts a file whose name contains wildcard-like characters to UTF-16 LE.

    .EXAMPLE
        PS > Set-FileEncoding -Path './report.txt' -Encoding UTF8BOM -Force -Verbose

        Rewrites the file as UTF-8 with BOM even if the detected encoding already matches.

    .OUTPUTS
        None by default.
        System.Management.Automation.PSCustomObject when -PassThru is specified.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Set-FileEncoding.ps1

        Converting to ASCII or ANSI can be lossy for characters that are not supported
        by the destination code page.

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Set-FileEncoding.ps1

    .LINK
        Get-EncodingFromName

    .LINK
        Get-FileEncoding
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Path')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Path')]
        [Alias('FullName', 'PSPath')]
        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [String[]]$Path,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'LiteralPath')]
        [Alias('LP')]
        [ValidateNotNullOrEmpty()]
        [String[]]$LiteralPath,

        [Parameter(Mandatory)]
        [ValidateSet('UTF8', 'UTF8BOM', 'UTF16LE', 'UTF16BE', 'UTF32', 'UTF32BE', 'ASCII', 'ANSI')]
        [String]$Encoding,

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        Write-Verbose "Starting Set-FileEncoding (Target Encoding: $Encoding, Force: $Force)"

        function Import-DependencyIfNeeded
        {
            param(
                [Parameter(Mandatory)]
                [String]$FunctionName,

                [Parameter(Mandatory)]
                [String]$RelativePath
            )

            if (-not (Get-Command -Name $FunctionName -ErrorAction Ignore))
            {
                $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
                $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

                if (-not (Test-Path -LiteralPath $dependencyPath -PathType Leaf))
                {
                    throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
                }

                return $dependencyPath
            }

            return $null
        }

        $dependencyPath = Import-DependencyIfNeeded -FunctionName 'Get-EncodingFromName' -RelativePath 'Get-EncodingFromName.ps1'
        if ($dependencyPath)
        {
            try
            {
                . $dependencyPath
                Write-Verbose "Loaded Get-EncodingFromName from: $dependencyPath"
            }
            catch
            {
                throw "Failed to load required dependency 'Get-EncodingFromName' from '$dependencyPath': $($_.Exception.Message)"
            }
        }

        $dependencyPath = Import-DependencyIfNeeded -FunctionName 'Get-FileEncoding' -RelativePath 'Get-FileEncoding.ps1'
        if ($dependencyPath)
        {
            try
            {
                . $dependencyPath
                Write-Verbose "Loaded Get-FileEncoding from: $dependencyPath"
            }
            catch
            {
                throw "Failed to load required dependency 'Get-FileEncoding' from '$dependencyPath': $($_.Exception.Message)"
            }
        }

        $targetEncoding = Get-EncodingFromName -EncodingName $Encoding
        if ($null -eq $targetEncoding)
        {
            throw "Failed to resolve target encoding '$Encoding'."
        }

        function Test-EncodingMatch
        {
            param(
                [Parameter(Mandatory)]
                [System.Text.Encoding]$SourceEncoding,

                [Parameter(Mandatory)]
                [System.Text.Encoding]$TargetEncoding
            )

            if ($SourceEncoding.CodePage -ne $TargetEncoding.CodePage)
            {
                return $false
            }

            $sourcePreamble = $SourceEncoding.GetPreamble()
            $targetPreamble = $TargetEncoding.GetPreamble()

            if ($sourcePreamble.Length -ne $targetPreamble.Length)
            {
                return $false
            }

            for ($i = 0; $i -lt $sourcePreamble.Length; $i++)
            {
                if ($sourcePreamble[$i] -ne $targetPreamble[$i])
                {
                    return $false
                }
            }

            return $true
        }

        function Test-BinaryFile
        {
            param(
                [Parameter(Mandatory)]
                [String]$FilePath
            )

            try
            {
                $stream = [System.IO.File]::OpenRead($FilePath)
                try
                {
                    if ($stream.Length -eq 0)
                    {
                        return $false
                    }

                    $sampleSize = [Math]::Min([int64]8192, $stream.Length)
                    $buffer = New-Object byte[] $sampleSize
                    $bytesRead = $stream.Read($buffer, 0, $sampleSize)

                    if ($bytesRead -eq 0)
                    {
                        return $false
                    }

                    $hasUtf32LeBom = $bytesRead -ge 4 -and $buffer[0] -eq 0xFF -and $buffer[1] -eq 0xFE -and $buffer[2] -eq 0x00 -and $buffer[3] -eq 0x00
                    $hasUtf32BeBom = $bytesRead -ge 4 -and $buffer[0] -eq 0x00 -and $buffer[1] -eq 0x00 -and $buffer[2] -eq 0xFE -and $buffer[3] -eq 0xFF
                    $hasUtf8Bom = $bytesRead -ge 3 -and $buffer[0] -eq 0xEF -and $buffer[1] -eq 0xBB -and $buffer[2] -eq 0xBF
                    $hasUtf16LeBom = $bytesRead -ge 2 -and $buffer[0] -eq 0xFF -and $buffer[1] -eq 0xFE -and -not $hasUtf32LeBom
                    $hasUtf16BeBom = $bytesRead -ge 2 -and $buffer[0] -eq 0xFE -and $buffer[1] -eq 0xFF

                    if ($hasUtf32LeBom -or $hasUtf32BeBom -or $hasUtf8Bom -or $hasUtf16LeBom -or $hasUtf16BeBom)
                    {
                        return $false
                    }

                    try
                    {
                        $utf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)
                        $decoded = $utf8NoBom.GetString($buffer, 0, $bytesRead)

                        if ($decoded.Length -gt 0)
                        {
                            $printableCount = 0
                            foreach ($char in $decoded.ToCharArray())
                            {
                                $charCode = [int]$char
                                if (($charCode -ge 32 -and $charCode -le 126) -or
                                    $charCode -eq 9 -or
                                    $charCode -eq 10 -or
                                    $charCode -eq 13 -or
                                    $charCode -ge 160)
                                {
                                    $printableCount++
                                }
                            }

                            $printableRatio = $printableCount / $decoded.Length
                            if ($printableRatio -ge 0.75)
                            {
                                return $false
                            }
                        }
                    }
                    catch
                    {
                        Write-Verbose "File '$FilePath' is not valid UTF-8 text."
                    }

                    $nullByteCount = 0
                    $printableByteCount = 0
                    for ($i = 0; $i -lt $bytesRead; $i++)
                    {
                        $byte = $buffer[$i]
                        if ($byte -eq 0)
                        {
                            $nullByteCount++
                        }

                        if (($byte -ge 32 -and $byte -le 126) -or $byte -eq 9 -or $byte -eq 10 -or $byte -eq 13)
                        {
                            $printableByteCount++
                        }
                    }

                    if ($nullByteCount -gt ($bytesRead * 0.10))
                    {
                        return $true
                    }

                    $printableRatio = $printableByteCount / $bytesRead
                    return $printableRatio -lt 0.60
                }
                finally
                {
                    $stream.Close()
                }
            }
            catch
            {
                Write-Verbose "Error analyzing file '$FilePath': $($_.Exception.Message)"
                return $true
            }
        }

        function Get-FileEncodingResult
        {
            param(
                [Parameter(Mandatory)]
                [String]$FilePath,

                [Parameter()]
                [System.Text.Encoding]$SourceEncoding,

                [Parameter(Mandatory)]
                [System.Text.Encoding]$TargetEncoding,

                [Parameter(Mandatory)]
                [Boolean]$EncodingChanged,

                [Parameter(Mandatory)]
                [Boolean]$Skipped,

                [Parameter(Mandatory)]
                [Boolean]$Forced,

                [Parameter(Mandatory)]
                [Boolean]$Success,

                [Parameter()]
                [String]$ErrorMessage
            )

            [PSCustomObject]@{
                FilePath = $FilePath
                SourceEncoding = if ($SourceEncoding) { $SourceEncoding.EncodingName } else { $null }
                TargetEncoding = $TargetEncoding.EncodingName
                EncodingChanged = $EncodingChanged
                Skipped = $Skipped
                Forced = $Forced
                Success = $Success
                Error = $ErrorMessage
            }
        }
    }

    process
    {
        $inputPaths = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { $LiteralPath } else { $Path }

        foreach ($inputPath in $inputPaths)
        {
            try
            {
                $items = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
                {
                    @(Get-Item -LiteralPath $inputPath -ErrorAction Stop)
                }
                else
                {
                    @(Get-Item -Path $inputPath -ErrorAction Stop)
                }
            }
            catch
            {
                $message = "Failed to resolve path '$inputPath': $($_.Exception.Message)"
                Write-Error $message

                if ($PassThru)
                {
                    Get-FileEncodingResult -FilePath $inputPath -TargetEncoding $targetEncoding -EncodingChanged $false -Skipped $false -Forced $Force.IsPresent -Success $false -ErrorMessage $message
                }

                continue
            }

            foreach ($item in $items)
            {
                if ($item.PSIsContainer)
                {
                    Write-Verbose "Skipping directory: $($item.FullName)"
                    continue
                }

                if (Test-BinaryFile -FilePath $item.FullName)
                {
                    Write-Warning "Skipping binary file: $($item.FullName)"
                    continue
                }

                try
                {
                    $sourceEncoding = $null
                    $sourceEncoding = Get-FileEncoding -FilePath $item.FullName
                    $encodingMatches = Test-EncodingMatch -SourceEncoding $sourceEncoding -TargetEncoding $targetEncoding

                    if ($encodingMatches -and -not $Force)
                    {
                        Write-Verbose "Skipping '$($item.FullName)' because it already matches the requested encoding."

                        if ($PassThru)
                        {
                            Get-FileEncodingResult -FilePath $item.FullName -SourceEncoding $sourceEncoding -TargetEncoding $targetEncoding -EncodingChanged $false -Skipped $true -Forced $false -Success $true
                        }

                        continue
                    }

                    $action = if ($encodingMatches -and $Force)
                    {
                        "Rewrite file using encoding $Encoding"
                    }
                    else
                    {
                        "Convert file encoding to $Encoding"
                    }

                    if ($PSCmdlet.ShouldProcess($item.FullName, $action))
                    {
                        $content = [System.IO.File]::ReadAllText($item.FullName, $sourceEncoding)
                        $originalAttributes = [System.IO.File]::GetAttributes($item.FullName)
                        $removedReadOnly = $false

                        try
                        {
                            if (($originalAttributes -band [System.IO.FileAttributes]::ReadOnly) -and $Force)
                            {
                                $writableAttributes = $originalAttributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                                [System.IO.File]::SetAttributes($item.FullName, $writableAttributes)
                                $removedReadOnly = $true
                            }

                            [System.IO.File]::WriteAllText($item.FullName, $content, $targetEncoding)
                            Write-Verbose "Wrote '$($item.FullName)' using $($targetEncoding.EncodingName)"
                        }
                        finally
                        {
                            if ($removedReadOnly)
                            {
                                [System.IO.File]::SetAttributes($item.FullName, $originalAttributes)
                            }
                        }

                        if ($PassThru)
                        {
                            Get-FileEncodingResult -FilePath $item.FullName -SourceEncoding $sourceEncoding -TargetEncoding $targetEncoding -EncodingChanged (-not $encodingMatches) -Skipped $false -Forced $Force.IsPresent -Success $true
                        }
                    }
                }
                catch
                {
                    $message = "Failed to set encoding for '$($item.FullName)': $($_.Exception.Message)"
                    Write-Error $message

                    if ($PassThru)
                    {
                        Get-FileEncodingResult -FilePath $item.FullName -SourceEncoding $sourceEncoding -TargetEncoding $targetEncoding -EncodingChanged $false -Skipped $false -Forced $Force.IsPresent -Success $false -ErrorMessage $message
                    }
                }
            }
        }
    }

    end
    {
        Write-Verbose 'Set-FileEncoding completed'
    }
}
