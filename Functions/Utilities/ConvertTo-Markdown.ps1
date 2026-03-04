function ConvertTo-Markdown
{
    <#
    .SYNOPSIS
        Converts a URL or local file path to Markdown using Pandoc.

    .DESCRIPTION
        Wraps the pandoc CLI to convert an HTTP(S) URL or local file path to Markdown.
        By default, Markdown content is written to stdout and returned as a string.
        Use -OutputPath to write the conversion result to a file.

    .PARAMETER InputObject
        The source to convert. Accepts:
        - HTTP/HTTPS URLs
        - Local file paths

        Supports pipeline input and accepts multiple values.

    .PARAMETER To
        Pandoc Markdown output format. Defaults to GitHub-flavored Markdown ('gfm').
        Accepted values: commonmark, commonmark_x, gfm, markdown, markdown_github, markdown_mmd, markdown_phpextra, markdown_strict, markua

    .PARAMETER From
        Optional explicit Pandoc input format (for example: html, docx, rst).
        If omitted, Pandoc auto-detects the input format when possible.

    .PARAMETER OutputPath
        Optional destination file path for Markdown output.
        When specified, only a single InputObject value is supported.

    .PARAMETER PandocArgs
        Additional arguments to append to the Pandoc command.

    .PARAMETER PassThru
        When -OutputPath is specified, returns the resolved output path after
        successful conversion.

    .EXAMPLE
        PS > ConvertTo-Markdown -InputObject 'https://example.com'

        Converts a web page to GitHub-flavored Markdown and returns the result.

    .EXAMPLE
        PS > ConvertTo-Markdown -InputObject './report.html' -OutputPath './report.md'

        Converts a local HTML file to Markdown and writes it to report.md.

    .EXAMPLE
        PS > ConvertTo-Markdown -InputObject './report.docx' -From docx -To gfm

        Converts a Word document to GitHub-flavored Markdown.

    .EXAMPLE
        PS > 'https://example.com', './notes.html' | ConvertTo-Markdown

        Converts multiple inputs from the pipeline and returns Markdown text for each input.

    .OUTPUTS
        System.String
            Markdown text (default) or output file path when using -OutputPath -PassThru.

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
        [ValidateSet(
            'commonmark',
            'commonmark_x',
            'gfm',
            'markdown',
            'markdown_github',
            'markdown_mmd',
            'markdown_phpextra',
            'markdown_strict',
            'markua'
        )]
        [String]$To = 'gfm',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$From,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$OutputPath,

        [Parameter()]
        [String[]]$PandocArgs,

        [Parameter()]
        [Switch]$PassThru
    )

    begin
    {
        $pandocCommand = Get-Command -Name 'pandoc' -ErrorAction SilentlyContinue
        if (-not $pandocCommand)
        {
            throw 'Pandoc is not installed or not available in PATH. Please install Pandoc and try again.'
        }
        Write-Verbose "Pandoc found at: $($pandocCommand.Source)"

        $processedCount = 0
        $resolvedOutputPath = $null
        if ($PSBoundParameters.ContainsKey('OutputPath'))
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

            if ($resolvedOutputPath -and $processedCount -gt 1)
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

            if ($resolvedOutputPath)
            {
                $pandocCallArgs += @('-o', $resolvedOutputPath)
            }

            $pandocCallArgs += $pandocInput

            $target = if ($resolvedOutputPath) { $resolvedOutputPath } else { 'stdout' }
            if (-not $PSCmdlet.ShouldProcess($item, "Convert to Markdown ($target)"))
            {
                continue
            }

            Write-Verbose "Executing: $($pandocCommand.Name) $($pandocCallArgs -join ' ')"
            $global:LASTEXITCODE = 0
            $pandocOutput = & $pandocCommand.Name @pandocCallArgs
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0)
            {
                throw "Pandoc failed for '$item' with exit code $exitCode."
            }

            if ($resolvedOutputPath)
            {
                if ($PassThru)
                {
                    Write-Output $resolvedOutputPath
                }
                continue
            }

            $markdownText = if ($null -eq $pandocOutput)
            {
                ''
            }
            else
            {
                @($pandocOutput) -join [Environment]::NewLine
            }

            Write-Output $markdownText
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
