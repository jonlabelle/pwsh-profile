function ConvertTo-Markdown
{
    <#
    .SYNOPSIS
        Converts a URL or local file path to Markdown using Pandoc.

    .DESCRIPTION
        Wraps the pandoc CLI to convert an HTTP(S) URL or local file path to Markdown.
        Conversion output is always written to a Markdown file.
        When -OutputPath is omitted, a file path is auto-generated from the URL
        or local input filename (for example, https://example.com => example-com.md).
        Use -OutputPath to write the conversion result to a specific file path.

        Dependencies:
        - Get-EncodingFromName: Resolves profile encoding names to .NET encoding instances.
        - Get-FileEncoding: Detects current output file encoding before optional conversion.

        Both dependencies are automatically loaded when needed.

    .PARAMETER InputObject
        The source to convert. Accepts:
        - HTTP/HTTPS URLs
        - Local file paths

        Supports pipeline input and accepts multiple values.

    .PARAMETER To
        Pandoc Markdown output format. Defaults to GitHub-flavored Markdown ('gfm').

        Accepted values: commonmark, commonmark_x, gfm, markdown, markdown_github,
        markdown_mmd, markdown_phpextra, markdown_strict, markua.

        Supports extension modifiers in Pandoc format syntax:
        FORMAT[+EXTENSION|-EXTENSION]...
        Example: gfm+task_lists+pipe_tables-smart

        To view all possible extensions, run:
        pandoc --list-extensions markdown

    .PARAMETER From
        Pandoc input format (for example: html, docx, rst).
        Defaults to html.

    .PARAMETER OutputPath
        Optional explicit destination file path for Markdown output.
        When specified, only a single InputObject value is supported.
        When omitted, an output path is auto-generated per input item.

    .PARAMETER PandocArgs
        Additional arguments to append to the Pandoc command.

    .PARAMETER Encoding
        Specifies the target output file encoding. When set to 'Auto' (default),
        the encoding produced by Pandoc is preserved.

        Valid values:
        - Auto: Preserve Pandoc output encoding (default)
        - UTF8: UTF-8 without BOM
        - UTF8BOM: UTF-8 with BOM
        - UTF16LE: UTF-16 Little Endian with BOM
        - UTF16BE: UTF-16 Big Endian with BOM
        - UTF32: UTF-32 Little Endian with BOM
        - UTF32BE: UTF-32 Big Endian with BOM
        - ASCII: 7-bit ASCII encoding
        - ANSI: System default ANSI encoding (code page dependent)

    .PARAMETER PassThru
        Returns the resolved output path after successful conversion:
        - Explicit -OutputPath path
        - Auto-generated path when -OutputPath is omitted

    .EXAMPLE
        PS > ConvertTo-Markdown -InputObject 'https://example.com'

        Converts a web page to GitHub-flavored Markdown and writes it to ./example-com.md.

    .EXAMPLE
        PS > ConvertTo-Markdown -InputObject './report.html' -OutputPath './report.md'

        Converts a local HTML file to Markdown and writes it to report.md.

    .EXAMPLE
        PS > ConvertTo-Markdown -InputObject './report.docx' -From docx -To gfm

        Converts a Word document to GitHub-flavored Markdown.

    .EXAMPLE
        PS > ConvertTo-Markdown -InputObject './report.html' -To 'gfm+task_lists+pipe_tables-smart'

        Converts HTML to GFM with task lists and pipe tables enabled, and smart typography disabled.

    .EXAMPLE
        PS > 'https://example.com', './notes.html' | ConvertTo-Markdown

        Converts multiple inputs from the pipeline and writes one auto-named
        markdown file per input.

    .EXAMPLE
        PS > ConvertTo-Markdown -InputObject './report.html' -Encoding 'UTF8BOM'

        Converts HTML to Markdown and rewrites the output file as UTF-8 with BOM.

    .OUTPUTS
        System.String
            Output file path when using -PassThru.

    .NOTES
        Requires Pandoc to be installed and available in PATH.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-Markdown.ps1

    .LINK
        https://pandoc.org/

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/ConvertTo-Markdown.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([String])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [Alias('Path', 'Url', 'Uri')]
        [ValidateNotNullOrEmpty()]
        [String[]]$InputObject,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                $value = [String]$_
                $pattern = '^(commonmark|commonmark_x|gfm|markdown|markdown_github|markdown_mmd|markdown_phpextra|markdown_strict|markua)([+-][a-z][a-z0-9_]*)*$'

                if ($value -notmatch $pattern)
                {
                    throw 'Value must be a Pandoc markdown writer (commonmark, commonmark_x, gfm, markdown, markdown_github, markdown_mmd, markdown_phpextra, markdown_strict, markua) optionally followed by extension modifiers such as +footnotes or -emoji.'
                }

                $true
            })]
        [String]$To = 'gfm',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet(
            'asciidoc',
            'biblatex',
            'bibtex',
            'bits',
            'commonmark',
            'commonmark_x',
            'creole',
            'csljson',
            'csv',
            'djot',
            'docbook',
            'docx',
            'dokuwiki',
            'endnotexml',
            'epub',
            'fb2',
            'gfm',
            'haddock',
            'html',
            'ipynb',
            'jats',
            'jira',
            'json',
            'latex',
            'man',
            'markdown',
            'markdown_github',
            'markdown_mmd',
            'markdown_phpextra',
            'markdown_strict',
            'mdoc',
            'mediawiki',
            'muse',
            'native',
            'odt',
            'opml',
            'org',
            'pod',
            'pptx',
            'ris',
            'rst',
            'rtf',
            't2t',
            'textile',
            'tikiwiki',
            'tsv',
            'twiki',
            'typst',
            'vimwiki',
            'xlsx',
            'xml'
        )]
        [String]$From = 'html',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$OutputPath,

        [Parameter()]
        [String[]]$PandocArgs,

        [Parameter()]
        [ValidateSet('Auto', 'UTF8', 'UTF8BOM', 'UTF16LE', 'UTF16BE', 'UTF32', 'UTF32BE', 'ASCII', 'ANSI')]
        [String]$Encoding = 'Auto',

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        # Helper function to load dependencies on demand
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
                Write-Verbose "$FunctionName is required - attempting to load it"

                # Resolve path from current script location
                $dependencyPath = Join-Path -Path $PSScriptRoot -ChildPath $RelativePath
                $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

                if (Test-Path -Path $dependencyPath -PathType Leaf)
                {
                    return $dependencyPath
                }
                else
                {
                    throw "Required function '$FunctionName' could not be found. Expected location: $dependencyPath"
                }
            }
            else
            {
                Write-Verbose "$FunctionName is already loaded"
                return $null
            }
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

        function ConvertTo-FileSlug
        {
            param(
                [Parameter()]
                [AllowNull()]
                [String]$Value
            )

            if ([String]::IsNullOrWhiteSpace($Value))
            {
                return $null
            }

            $decoded = [Uri]::UnescapeDataString($Value)
            $slug = $decoded.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
            $slug = $slug.Trim('-')

            if ([String]::IsNullOrWhiteSpace($slug))
            {
                return $null
            }

            return $slug
        }

        function Get-MarkdownOutputPathFromUri
        {
            param(
                [Parameter(Mandatory)]
                [Uri]$Uri
            )

            $hostSlug = ConvertTo-FileSlug -Value $Uri.DnsSafeHost
            if (-not $hostSlug)
            {
                $hostSlug = 'web-page'
            }

            $pathSegmentSlugs = @()
            $pathSegments = $Uri.AbsolutePath.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
            foreach ($segment in $pathSegments)
            {
                $segmentWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($segment)
                $segmentSlug = ConvertTo-FileSlug -Value $segmentWithoutExtension
                if ($segmentSlug)
                {
                    $pathSegmentSlugs += $segmentSlug
                }
            }

            $baseName = if ($pathSegmentSlugs.Count -gt 0)
            {
                @($hostSlug) + $pathSegmentSlugs -join '-'
            }
            else
            {
                $hostSlug
            }

            if ($Uri.Query)
            {
                $querySlug = ConvertTo-FileSlug -Value $Uri.Query.TrimStart('?')
                if ($querySlug)
                {
                    $baseName = "$baseName-$querySlug"
                }
            }

            $fileName = "$baseName.md"
            return Join-Path -Path (Get-Location).Path -ChildPath $fileName
        }

        function Get-MarkdownOutputPathFromLocalSource
        {
            param(
                [Parameter(Mandatory)]
                [String]$Path
            )

            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            $baseSlug = ConvertTo-FileSlug -Value $baseName
            if (-not $baseSlug)
            {
                $baseSlug = 'document'
            }

            $fileName = "$baseSlug.md"
            return Join-Path -Path (Get-Location).Path -ChildPath $fileName
        }

        $pandocCommand = Get-Command -Name 'pandoc' -ErrorAction SilentlyContinue
        if (-not $pandocCommand)
        {
            throw 'Pandoc is not installed or not available in PATH. Please install Pandoc and try again.'
        }
        Write-Verbose "Pandoc found at: $($pandocCommand.Source)"

        $pandocRequestUserAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36'

        $processedCount = 0
        $hasExplicitOutputPath = $PSBoundParameters.ContainsKey('OutputPath')
        $resolvedOutputPath = $null
        if ($hasExplicitOutputPath)
        {
            $resolvedOutputPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
            $outputDirectory = Split-Path -Path $resolvedOutputPath -Parent
            if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container))
            {
                $null = New-Item -Path $outputDirectory -ItemType Directory -Force
            }
            Write-Verbose "Markdown output path resolved to: $resolvedOutputPath"
        }
    }

    process
    {
        foreach ($item in $InputObject)
        {
            $processedCount++

            if ($hasExplicitOutputPath -and $processedCount -gt 1)
            {
                throw 'When -OutputPath is specified, only one InputObject value is supported.'
            }

            $parsedUri = $null
            $isWebUri = [Uri]::TryCreate($item, [UriKind]::Absolute, [ref]$parsedUri) -and
            $parsedUri.Scheme -in @('http', 'https')

            if ($isWebUri)
            {
                $pandocInput = $parsedUri.AbsoluteUri
            }
            else
            {
                if (-not (Test-Path -LiteralPath $item -PathType Leaf))
                {
                    throw "Input path does not exist or is not a file: $item"
                }

                $pandocInput = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($item)
            }

            $autoOutputPath = $null
            if (-not $hasExplicitOutputPath)
            {
                if ($isWebUri)
                {
                    $autoOutputPath = Get-MarkdownOutputPathFromUri -Uri $parsedUri
                }
                else
                {
                    $autoOutputPath = Get-MarkdownOutputPathFromLocalSource -Path $pandocInput
                }

                Write-Verbose "Auto-generated markdown output path: $autoOutputPath"
            }

            $effectiveOutputPath = if ($hasExplicitOutputPath) { $resolvedOutputPath } else { $autoOutputPath }

            $pandocCallArgs = @()
            if ($From)
            {
                $pandocCallArgs += @('--from', $From)
            }
            $pandocCallArgs += @('--to', $To)

            if ($PandocArgs)
            {
                $pandocCallArgs += $PandocArgs
            }
            $pandocCallArgs += "--request-header=User-Agent: $pandocRequestUserAgent"

            if ($effectiveOutputPath)
            {
                $pandocCallArgs += @('-o', $effectiveOutputPath)
            }

            $pandocCallArgs += $pandocInput

            $target = $effectiveOutputPath

            if (-not $PSCmdlet.ShouldProcess($item, "Convert to Markdown ($target)"))
            {
                continue
            }

            Write-Verbose "Executing: $($pandocCommand.Name) $($pandocCallArgs -join ' ')"
            $global:LASTEXITCODE = 0
            $null = & $pandocCommand.Name @pandocCallArgs
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0)
            {
                throw "Pandoc failed for '$item' with exit code $exitCode."
            }

            if ($Encoding -ne 'Auto' -and $effectiveOutputPath)
            {
                $targetEncoding = Get-EncodingFromName -EncodingName $Encoding
                if ($null -eq $targetEncoding)
                {
                    throw "Failed to resolve target encoding '$Encoding'."
                }

                $sourceEncoding = Get-FileEncoding -FilePath $effectiveOutputPath

                $sourceType = $sourceEncoding.ToString()
                $targetType = $targetEncoding.ToString()
                $sourceBomLength = $sourceEncoding.GetPreamble().Length
                $targetBomLength = $targetEncoding.GetPreamble().Length
                $encodingMatches = ($sourceType -eq $targetType) -and ($sourceBomLength -eq $targetBomLength)

                if (-not $encodingMatches)
                {
                    $reader = New-Object System.IO.StreamReader($effectiveOutputPath, $sourceEncoding, $true)
                    try
                    {
                        $markdownContent = $reader.ReadToEnd()
                    }
                    finally
                    {
                        $reader.Close()
                    }

                    $preamble = $targetEncoding.GetPreamble()
                    $contentBytes = $targetEncoding.GetBytes($markdownContent)
                    if ($preamble.Length -gt 0)
                    {
                        $newBytes = New-Object byte[] ($preamble.Length + $contentBytes.Length)
                        [Array]::Copy($preamble, 0, $newBytes, 0, $preamble.Length)
                        [Array]::Copy($contentBytes, 0, $newBytes, $preamble.Length, $contentBytes.Length)
                    }
                    else
                    {
                        $newBytes = $contentBytes
                    }

                    [System.IO.File]::WriteAllBytes($effectiveOutputPath, $newBytes)
                }
            }

            if ($PassThru)
            {
                Write-Output $effectiveOutputPath
            }
        }
    }
}

# Create 'url2markdown' alias only if it doesn't already exist
if (-not (Get-Command -Name 'url2markdown' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'url2markdown' alias for ConvertTo-Markdown"
        Set-Alias -Name 'url2markdown' -Value 'ConvertTo-Markdown' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "ConvertTo-Markdown: Could not create 'url2markdown' alias: $($_.Exception.Message)"
    }
}
