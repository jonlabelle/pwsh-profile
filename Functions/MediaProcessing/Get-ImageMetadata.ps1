function Get-ImageMetadata
{
    <#
    .SYNOPSIS
        Retrieves embedded metadata from image files.

    .DESCRIPTION
        Retrieves image metadata using ExifTool and returns structured PowerShell
        objects. The function can inspect individual image files, directories, or
        wildcard paths. Directory searches are non-recursive by default; use
        -Recurse to include subdirectories.

        By default, all available ExifTool tag groups are requested with group
        names included in the returned metadata keys, such as EXIF:Make,
        GPS:GPSLatitude, XMP:Title, or File:ImageSize. Use -Tag to request a
        smaller set of ExifTool tags or tag groups.

        Dependencies:
        - `exiftool` must be available in PATH or specified via -ExifToolPath.

    .PARAMETER Path
        One or more image file or directory paths to inspect. Accepts pipeline
        input and wildcard patterns. Defaults to the current working directory.

    .PARAMETER Filters
        File name filters to use when searching directories. Defaults to common
        image extensions including JPEG, PNG, TIFF, WebP, HEIC, AVIF, GIF, and BMP.

    .PARAMETER Exclude
        Directory names to exclude when -Recurse is specified. Defaults to
        @('.git', 'node_modules', '.vscode').

    .PARAMETER Recurse
        Searches directories recursively. By default, only files directly inside
        each directory are inspected.

    .PARAMETER ExifToolPath
        Path to the ExifTool executable. If omitted, the function searches PATH
        and common platform-specific install locations.

    .PARAMETER Tag
        One or more ExifTool tags or tag groups to request, such as EXIF:Make,
        GPS:all, XMP:Title, File:ImageSize, or -DateTimeOriginal. A leading dash
        is optional.

    .PARAMETER Flatten
        Returns one object per metadata tag instead of one object per image.

    .PARAMETER NoEmptyProperties
        Excludes metadata tags whose values are null, empty strings, or empty
        arrays.

    .PARAMETER Numeric
        Requests numeric ExifTool output by passing -n.

    .PARAMETER IncludeRawExifToolData
        Adds the parsed raw ExifTool JSON object to each non-flattened result.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\photo.jpg'

        Retrieves all available metadata from photo.jpg.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\Images'

        Retrieves metadata from supported image files directly inside the Images folder.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\Images' -Recurse

        Recursively retrieves metadata from supported image files under the Images folder.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\Images' -Recurse -Exclude @('.git', 'raw')

        Recursively retrieves image metadata while skipping .git and raw directories.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\Images' -Filters '*.jpg', '*.png'

        Retrieves metadata only from JPEG and PNG files in the Images folder.

    .EXAMPLE
        PS > Get-ChildItem -Path '.\Uploads' -Filter '*.jpg' | Get-ImageMetadata

        Retrieves metadata from JPEG files provided through the pipeline.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\photo.jpg' -Tag EXIF:Make, EXIF:Model, GPS:all

        Retrieves only camera make, camera model, and GPS tags.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\photo.jpg' -Tag DateTimeOriginal -Numeric

        Retrieves DateTimeOriginal while requesting numeric ExifTool output.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\photo.jpg' -Flatten

        Returns one object per metadata tag with Path, Group, Tag, Name, and Value properties.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\photo.jpg' -Flatten | Where-Object Group -eq 'GPS'

        Displays only GPS metadata tags from photo.jpg.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\photo.jpg' -NoEmptyProperties

        Retrieves metadata and omits empty tag values from the Metadata property.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\photo.jpg' -IncludeRawExifToolData

        Includes the parsed raw ExifTool JSON object with the structured result.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\*.jpeg' -Flatten | Format-Table Path, Group, Tag, Value

        Retrieves flattened metadata for all JPEG files matching the wildcard pattern.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\Photos' -Tag GPS:all -Recurse -NoEmptyProperties

        Recursively inspects a photo folder for non-empty GPS tags.

    .EXAMPLE
        PS > Get-ImageMetadata -Path '.\photo.jpg' -ExifToolPath '/opt/homebrew/bin/exiftool'

        Uses a specific ExifTool executable to retrieve image metadata.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns one object per image by default. With -Flatten, returns one object
        per image metadata tag.

    .NOTES
        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/MediaProcessing/Get-ImageMetadata.ps1

    .LINK
        https://exiftool.org/

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/MediaProcessing/Get-ImageMetadata.ps1
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Metadata is a mass noun in this command name.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Directory', 'Folder', 'Location', 'FilePath', 'FullName')]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Path = @($PWD.Path),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Filters = @('*.jpg', '*.jpeg', '*.png', '*.tif', '*.tiff', '*.webp', '*.heic', '*.heif', '*.avif', '*.gif', '*.bmp'),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Exclude = @('.git', 'node_modules', '.vscode'),

        [Parameter()]
        [Switch]
        $Recurse,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]
        $ExifToolPath,

        [Parameter()]
        [Alias('Tags')]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Tag = @(),

        [Parameter()]
        [Switch]
        $Flatten,

        [Parameter()]
        [Switch]
        $NoEmptyProperties,

        [Parameter()]
        [Switch]
        $Numeric,

        [Parameter()]
        [Switch]
        $IncludeRawExifToolData
    )

    begin
    {
        Write-Verbose 'Starting image metadata retrieval'

        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            $script:IsWindowsPlatform = $true
            $script:IsMacOSPlatform = $false
            $script:IsLinuxPlatform = $false
        }
        else
        {
            $script:IsWindowsPlatform = $IsWindows
            $script:IsMacOSPlatform = $IsMacOS
            $script:IsLinuxPlatform = $IsLinux
        }

        function Get-ImageMetadataLinuxPackageManagerHint
        {
            $aptCommand = Get-Command -Name 'apt' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
            if ($aptCommand)
            {
                return 'apt'
            }

            $apkCommand = Get-Command -Name 'apk' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
            if ($apkCommand)
            {
                return 'apk'
            }

            $brewCommand = Get-Command -Name 'brew' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
            if ($brewCommand)
            {
                return 'brew'
            }

            if (-not (Test-Path -Path '/etc/os-release' -PathType Leaf))
            {
                return ''
            }

            try
            {
                $linuxIds = @()
                foreach ($line in (Get-Content -Path '/etc/os-release' -ErrorAction Stop))
                {
                    if ($line -match '^(?<Name>ID|ID_LIKE)=(?<Value>.+)$')
                    {
                        $linuxIds += $Matches.Value.Trim().Trim('"')
                    }
                }

                $linuxFamily = ($linuxIds -join ' ').ToLowerInvariant()
                if ($linuxFamily -match '\balpine\b')
                {
                    return 'apk'
                }

                if ($linuxFamily -match '\b(debian|ubuntu)\b')
                {
                    return 'apt'
                }
            }
            catch
            {
                Write-Verbose "Unable to detect Linux package manager for install hint: $($_.Exception.Message)"
            }

            return ''
        }

        function Get-ImageMetadataInstallPackageHint
        {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('ExifTool')]
                [String]$RequirementName
            )

            $installerCommand = 'Install-PlatformPackage'

            if ($script:IsWindowsPlatform)
            {
                switch ($RequirementName)
                {
                    'ExifTool' { return "$installerCommand -Id OliverBetz.ExifTool" }
                }
            }

            if ($script:IsMacOSPlatform)
            {
                switch ($RequirementName)
                {
                    'ExifTool' { return "$installerCommand -Name exiftool" }
                }
            }

            if ($script:IsLinuxPlatform)
            {
                $linuxPackageManager = Get-ImageMetadataLinuxPackageManagerHint
                switch ($linuxPackageManager)
                {
                    'apt'
                    {
                        switch ($RequirementName)
                        {
                            'ExifTool' { return "$installerCommand -Name libimage-exiftool-perl" }
                        }
                    }
                    'apk'
                    {
                        switch ($RequirementName)
                        {
                            'ExifTool' { return "$installerCommand -Name exiftool" }
                        }
                    }
                    'brew'
                    {
                        switch ($RequirementName)
                        {
                            'ExifTool' { return "$installerCommand -Name exiftool" }
                        }
                    }
                }
            }

            return ''
        }

        function Get-ImageMetadataMissingRequirementMessage
        {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('ExifTool')]
                [String]$RequirementName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$PathParameterName
            )

            $message = "$RequirementName executable not found. Install $RequirementName or specify the path using -$PathParameterName."
            $installPackageHint = Get-ImageMetadataInstallPackageHint -RequirementName $RequirementName

            if (-not [String]::IsNullOrWhiteSpace($installPackageHint))
            {
                $message = "$message Hint: run: $installPackageHint (function path: ./Functions/SystemAdministration/Install-PlatformPackage.ps1)."
            }

            return $message
        }

        function Get-ValidExifToolPath
        {
            param([String]$ProvidedPath)

            $resolvedPath = $ProvidedPath

            if ($resolvedPath)
            {
                $resolvedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($resolvedPath)
            }

            if (-not $resolvedPath)
            {
                $exifToolCommand = Get-Command -Name 'exiftool' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
                Select-Object -First 1

                if ($exifToolCommand)
                {
                    if ($exifToolCommand.Path)
                    {
                        $resolvedPath = $exifToolCommand.Path
                    }
                    else
                    {
                        $resolvedPath = $exifToolCommand.Source
                    }

                    Write-Verbose "Using ExifTool from PATH: $resolvedPath"
                }
                else
                {
                    if ($script:IsWindowsPlatform)
                    {
                        $commonPaths = @(
                            'C:\Windows\exiftool.exe',
                            'C:\Program Files\ExifTool\exiftool.exe',
                            'C:\Program Files (x86)\ExifTool\exiftool.exe',
                            "$env:USERPROFILE\scoop\apps\exiftool\current\exiftool.exe",
                            "$env:ProgramData\chocolatey\bin\exiftool.exe"
                        )
                    }
                    elseif ($script:IsMacOSPlatform)
                    {
                        $commonPaths = @(
                            '/opt/homebrew/bin/exiftool',
                            '/usr/local/bin/exiftool',
                            '/opt/local/bin/exiftool',
                            "$env:HOME/.local/bin/exiftool",
                            "$env:HOME/bin/exiftool"
                        )
                    }
                    else
                    {
                        $commonPaths = @(
                            '/usr/bin/exiftool',
                            '/usr/local/bin/exiftool',
                            '/snap/bin/exiftool',
                            "$env:HOME/.local/bin/exiftool",
                            "$env:HOME/bin/exiftool"
                        )
                    }

                    foreach ($pathCandidate in $commonPaths)
                    {
                        if (Test-Path -LiteralPath $pathCandidate -PathType Leaf)
                        {
                            $resolvedPath = $pathCandidate
                            Write-Verbose "Found ExifTool at: $resolvedPath"
                            break
                        }
                    }
                }
            }

            if (-not $resolvedPath -or -not (Test-Path -LiteralPath $resolvedPath -PathType Leaf))
            {
                throw (Get-ImageMetadataMissingRequirementMessage -RequirementName 'ExifTool' -PathParameterName 'ExifToolPath')
            }

            return $resolvedPath
        }

        function Test-ImageFileName
        {
            param([System.IO.FileInfo]$FileInfo)

            foreach ($filter in $Filters)
            {
                if ($FileInfo.Name -like $filter)
                {
                    return $true
                }
            }

            return $false
        }

        function Test-ExcludedDirectory
        {
            param([System.IO.FileInfo]$FileInfo)

            if (-not $Recurse -or -not $FileInfo.DirectoryName -or $Exclude.Count -eq 0)
            {
                return $false
            }

            $directoryParts = $FileInfo.DirectoryName -split '[\\/]'
            foreach ($excludeDirectory in $Exclude)
            {
                if ($directoryParts -contains $excludeDirectory)
                {
                    return $true
                }
            }

            return $false
        }

        function Test-EmptyMetadataValue
        {
            param([Object]$Value)

            if ($null -eq $Value)
            {
                return $true
            }

            if ($Value -is [String] -and [String]::IsNullOrWhiteSpace($Value))
            {
                return $true
            }

            if ($Value -is [Array] -and $Value.Count -eq 0)
            {
                return $true
            }

            return $false
        }

        function Resolve-ImageMetadataPath
        {
            param([String]$InputPath)

            if ([String]::IsNullOrWhiteSpace($InputPath))
            {
                Write-Warning 'Path parameter is null or empty, skipping.'
                return @()
            }

            try
            {
                if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($InputPath))
                {
                    $resolvedItems = @(Resolve-Path -Path $InputPath -ErrorAction Stop)
                }
                else
                {
                    $resolvedProviderPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InputPath)
                    $resolvedItems = @([PSCustomObject]@{ Path = $resolvedProviderPath })
                }
            }
            catch
            {
                Write-Error $_.Exception.Message
                return @()
            }

            $imageFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

            foreach ($resolvedItem in $resolvedItems)
            {
                $resolvedPath = $resolvedItem.Path

                if (-not (Test-Path -LiteralPath $resolvedPath))
                {
                    Write-Error "Path not found: '$resolvedPath'"
                    continue
                }

                $pathItem = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop

                if ($pathItem.PSIsContainer)
                {
                    foreach ($filter in $Filters)
                    {
                        $childItemParams = @{
                            LiteralPath = $pathItem.FullName
                            Filter = $filter
                            File = $true
                            ErrorAction = 'Stop'
                        }

                        if ($Recurse)
                        {
                            $childItemParams.Recurse = $true
                        }

                        try
                        {
                            $filesForFilter = @(Get-ChildItem @childItemParams)
                        }
                        catch
                        {
                            Write-Error $_.Exception.Message
                            continue
                        }

                        foreach ($fileForFilter in $filesForFilter)
                        {
                            if (-not (Test-ExcludedDirectory -FileInfo $fileForFilter))
                            {
                                $imageFiles.Add($fileForFilter)
                            }
                        }
                    }
                }
                elseif ($pathItem -is [System.IO.FileInfo])
                {
                    if (Test-ImageFileName -FileInfo $pathItem)
                    {
                        $imageFiles.Add($pathItem)
                    }
                    else
                    {
                        Write-Warning "Skipping unsupported image file extension: '$($pathItem.FullName)'"
                    }
                }
            }

            return @($imageFiles)
        }

        function ConvertTo-ExifToolTagArgument
        {
            param([String]$TagName)

            $trimmedTagName = $TagName.Trim()
            if ($trimmedTagName.StartsWith('-'))
            {
                return $trimmedTagName
            }

            return "-$trimmedTagName"
        }

        function Split-ExifToolPropertyName
        {
            param([String]$PropertyName)

            if ($PropertyName -match '^(?<Group>[^:]+):(?<Tag>.+)$')
            {
                return [PSCustomObject]@{
                    Group = $Matches.Group
                    Tag = $Matches.Tag
                }
            }

            return [PSCustomObject]@{
                Group = $null
                Tag = $PropertyName
            }
        }

        function Invoke-ExifToolImageMetadata
        {
            param([String]$FilePath)

            $exifToolArgs = @(
                '-j'
                '-a'
                '-G1'
                '-struct'
            )

            if ($Numeric)
            {
                $exifToolArgs += '-n'
            }

            if ($Tag.Count -gt 0)
            {
                foreach ($tagName in $Tag)
                {
                    $exifToolArgs += ConvertTo-ExifToolTagArgument -TagName $tagName
                }
            }
            else
            {
                $exifToolArgs += '-all:all'
            }

            $exifToolArgs += $FilePath

            Write-Verbose "ExifTool command: $exifToolExecutable $($exifToolArgs -join ' ')"

            $global:LASTEXITCODE = 0
            $commandOutput = @(& $exifToolExecutable @exifToolArgs 2>&1)
            $exitCode = $LASTEXITCODE

            $stdoutLines = [System.Collections.Generic.List[String]]::new()
            $stderrLines = [System.Collections.Generic.List[String]]::new()

            foreach ($outputItem in $commandOutput)
            {
                if ($outputItem -is [System.Management.Automation.ErrorRecord])
                {
                    $stderrLines.Add($outputItem.Exception.Message)
                }
                else
                {
                    $stdoutLines.Add("$outputItem")
                }
            }

            $stdout = ($stdoutLines -join [Environment]::NewLine)
            $stderr = ($stderrLines -join [Environment]::NewLine)

            if ($exitCode -ne 0)
            {
                throw "ExifTool failed for '$FilePath' with exit code $exitCode. $stderr"
            }

            if ([String]::IsNullOrWhiteSpace($stdout))
            {
                throw "ExifTool returned no metadata for '$FilePath'. $stderr"
            }

            try
            {
                $parsedMetadata = $stdout | ConvertFrom-Json
            }
            catch
            {
                throw "Failed to parse ExifTool JSON output for '$FilePath': $($_.Exception.Message)"
            }

            $metadataObjects = @($parsedMetadata)
            if ($metadataObjects.Count -eq 0)
            {
                throw "ExifTool returned no metadata object for '$FilePath'."
            }

            return [PSCustomObject]@{
                MetadataObject = $metadataObjects[0]
                ExitCode = $exitCode
                Message = $stderr
            }
        }

        function ConvertTo-ImageMetadataMap
        {
            param([PSCustomObject]$MetadataObject)

            $metadata = [ordered]@{}
            foreach ($property in $MetadataObject.PSObject.Properties)
            {
                if ($property.Name -eq 'SourceFile')
                {
                    continue
                }

                if ($NoEmptyProperties -and (Test-EmptyMetadataValue -Value $property.Value))
                {
                    continue
                }

                $metadata[$property.Name] = $property.Value
            }

            return $metadata
        }

        function ConvertTo-ImageMetadataRow
        {
            param(
                [System.IO.FileInfo]$FileInfo,
                [PSCustomObject]$MetadataObject
            )

            foreach ($property in $MetadataObject.PSObject.Properties)
            {
                if ($property.Name -eq 'SourceFile')
                {
                    continue
                }

                if ($NoEmptyProperties -and (Test-EmptyMetadataValue -Value $property.Value))
                {
                    continue
                }

                $nameParts = Split-ExifToolPropertyName -PropertyName $property.Name

                [PSCustomObject]@{
                    Path = $FileInfo.FullName
                    Name = $FileInfo.Name
                    Extension = $FileInfo.Extension
                    Group = $nameParts.Group
                    Tag = $nameParts.Tag
                    MetadataName = $property.Name
                    Value = $property.Value
                }
            }
        }

        $exifToolExecutable = Get-ValidExifToolPath -ProvidedPath $ExifToolPath
        $processedCount = 0
        $failedCount = 0
    }

    process
    {
        $imageFilesByPath = @{}

        foreach ($currentPath in $Path)
        {
            foreach ($imageFile in (Resolve-ImageMetadataPath -InputPath $currentPath))
            {
                if (-not $imageFilesByPath.ContainsKey($imageFile.FullName))
                {
                    $imageFilesByPath[$imageFile.FullName] = $imageFile
                }
            }
        }

        $imageFilesToProcess = @(
            $imageFilesByPath.GetEnumerator() |
            Sort-Object -Property Name |
            ForEach-Object { $_.Value }
        )

        foreach ($imageFile in $imageFilesToProcess)
        {
            $processedCount++

            try
            {
                $metadataResult = Invoke-ExifToolImageMetadata -FilePath $imageFile.FullName

                if ($Flatten)
                {
                    ConvertTo-ImageMetadataRow -FileInfo $imageFile -MetadataObject $metadataResult.MetadataObject
                    continue
                }

                $metadata = ConvertTo-ImageMetadataMap -MetadataObject $metadataResult.MetadataObject
                $result = [PSCustomObject]@{
                    Path = $imageFile.FullName
                    Name = $imageFile.Name
                    Extension = $imageFile.Extension
                    SizeBytes = $imageFile.Length
                    CreatedDate = $imageFile.CreationTime
                    ModifiedDate = $imageFile.LastWriteTime
                    TagCount = $metadata.Count
                    Metadata = $metadata
                }

                if ($IncludeRawExifToolData)
                {
                    $result | Add-Member -NotePropertyName 'RawExifToolData' -NotePropertyValue $metadataResult.MetadataObject
                }

                if (-not [String]::IsNullOrWhiteSpace($metadataResult.Message))
                {
                    $result | Add-Member -NotePropertyName 'ExifToolMessage' -NotePropertyValue $metadataResult.Message
                }

                $result
            }
            catch
            {
                $failedCount++
                Write-Error $_.Exception.Message
            }
        }
    }

    end
    {
        Write-Verbose "Image metadata retrieval complete. Processed: $processedCount; Failed: $failedCount"
    }
}
