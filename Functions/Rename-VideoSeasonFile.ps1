function Rename-VideoSeasonFile
{
    <#
    .SYNOPSIS
        Renames files into their proper season sequence format.

    .DESCRIPTION
        This function searches for video files with season/episode identifiers in their names
        (patterns like S01E01) and renames them to a standardized uppercase format. It's useful
        for organizing TV show collections to ensure consistent naming across all files.

        The function looks for patterns like s01e01 or S01E01 in filenames and renames the file
        to use the uppercase version (S01E01) while preserving the file extension.

    .PARAMETER Path
        The directory path to search for video files.
        Default is the current working directory.

    .PARAMETER Filters
        The file extensions to search for.
        Default filters are @('*.mkv', '*.mp4', '*.mov', '*.avi').

    .PARAMETER WhatIf
        When specified, shows what would happen if the command runs but doesn't perform the actual rename operation.

    .PARAMETER Exclude
        Specifies paths to exclude from the search.
        Default exclusions are @('.git', 'node_modules').

    .EXAMPLE
        PS> Rename-VideoSeasonFile -Verbose -WhatIf
        Displays what would happen if the function ran with the default options, showing which files would be renamed.

    .EXAMPLE
        PS> Rename-VideoSeasonFile -Path 'D:\TV Shows\Breaking Bad' -Filters '*.mp4' -Verbose
        Renames all MP4 files in the specified directory that contain season identifiers.

    .EXAMPLE
        PS> Rename-VideoSeasonFile -Path 'D:\Downloads' -Exclude @('.git', 'node_modules', 'temp')
        Renames video files in the Downloads folder, excluding any in the specified directories.

    .NOTES
        Version: 1.1.0
        Date: January 14, 2023
        Author: Jon LaBelle
        License: MIT

    .LINK
        https://jonlabelle.com/snippets/view/powershell/rename-video-season-sequence-files-in-powershell
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
