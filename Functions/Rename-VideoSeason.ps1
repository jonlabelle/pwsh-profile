function Rename-VideoSeasonFile
{
    <#
        .SYNOPSIS
            Renames files into their proper season sequence format.

        .PARAMETER Path
            The directory path to search.
            The default is the current working directory.

        .PARAMETER Filters
            The file filters to search.
            The default filters are @('*.mkv', '*.mp4', '*.mov', '*.avi')

        .PARAMETER WhatIf
            If specified, the file rename operation will not be performed.

        .PARAMETER Exclude
            Paths to exclude.
            The default exclusions paths are @('.git', 'node_modules')

        .EXAMPLE
            PS > Rename-VideoSeason -Verbose -WhatIf

            To show what would happen using the default options.

        .EXAMPLE
            PS > Rename-VideoSeason -Path 'path/to/season' -Filters '*.mp4' -Verbose

            To rename mp4 files with season sequence format.

        .LINK
            https://jonlabelle.com/snippets/view/powershell/rename-video-season-sequence-files-in-powershell

        .NOTES
            Version: 1.1.0
            Date: January 14, 2023
            Author: Jon LaBelle
            License: MIT
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [String]
        $Path = $pwd,

        [Parameter()]
        [String[]]
        $Filters = @('*.mkv', '*.mp4', '*.mov', '*.avi'),

        [Parameter()]
        [String[]]
        $Exclude = @('.git', 'node_modules')
    )

    if (-not [System.String]::IsNullOrWhiteSpace($Path))
    {
        foreach ($filter in $Filters)
        {
            $files = @(Get-ChildItem -Path $Path -Filter $filter -Recurse -File -Exclude $Exclude | Where-Object { $_.BaseName -cmatch '[Ss]\d{2}[Ee]\d{2}' })

            foreach ($file in $files)
            {
                Write-Verbose ("Checking '{0}' in '{1}'" -f $file.Name, $file.Directory.FullName)

                if ($file.BaseName -cmatch '[Ss]\d{2}[Ee]\d{2}')
                {
                    $fileExtension = $file.Extension
                    $matchedFile = $Matches.0

                    if (-not $matchedFile)
                    {
                        Write-Verbose ("Regex numbered matching group returned null, ignoring file '{0}'" -f $file.FullName)
                        continue
                    }

                    if ($matchedFile -ceq $file.BaseName.ToUpper())
                    {
                        Write-Verbose ("'{0}' is already formatted" -f $file.Name)
                    }
                    else
                    {
                        if ($PSCmdlet.ShouldProcess($file.FullName, 'Rename file'))
                        {
                            $newFileName = ('{0}{1}' -f $matchedFile.ToUpper().Trim(), $fileExtension.ToLower().Trim())
                            Move-Item -LiteralPath $file.FullName -Destination (Join-Path -Path $file.DirectoryName -ChildPath $newFileName)
                        }
                    }
                }
                else
                {
                    Write-Verbose ("File does not match rename criteria: '{0}'" -f $file.FullName)
                }
            }
        }
    }
}
