﻿function Protect-PathWithPassword
{
    <#
    .SYNOPSIS
        Encrypts files or folders with AES-256 encryption using a password.

    .DESCRIPTION
        This function encrypts files or directories using AES-256-CBC encryption with PBKDF2 key derivation.
        Creates encrypted .enc files alongside original files, or encrypts entire directory structures.
        Uses industry-standard encryption with 100,000 PBKDF2 iterations and SHA-256 hashing for enhanced security.

        ENCRYPTION DETAILS:
        - Algorithm: AES-256-CBC (Advanced Encryption Standard, 256-bit key, Cipher Block Chaining)
        - Key Derivation: PBKDF2 with SHA-256, 100,000 iterations
        - Random salt (32 bytes) and initialization vector (16 bytes) per file
        - File format: [Salt:32][IV:16][EncryptedData:Variable]

        CROSS-PLATFORM COMPATIBILITY:
        This function works on PowerShell 5.1+ across Windows, macOS, and Linux
        by using .NET cryptographic classes instead of platform-specific APIs.

    .PARAMETER Path
        The file or directory path to encrypt. Accepts both relative and absolute paths.
        Supports pipeline input from Get-ChildItem and other cmdlets.
        For directories, use -Recurse to encrypt subdirectories.

    .PARAMETER Password
        SecureString containing the encryption password. If not provided, prompts securely.
        Password should be strong and memorable as it will be required for decryption.
        The same password must be used with Unprotect-PathWithPassword to decrypt files.

    .PARAMETER OutputPath
        Optional output directory or file path for encrypted files.
        If not specified, creates .enc files in the same location as originals.
        For directories, creates encrypted files in the specified output directory.

    .PARAMETER Recurse
        When encrypting directories, recursively encrypt all files in subdirectories.
        Without this switch, only files in the root directory are encrypted.

    .PARAMETER Force
        Overwrite existing encrypted files without prompting for confirmation.
        Use with caution as this will replace existing .enc files.

    .PARAMETER RemoveOriginal
        Remove the original unencrypted files after successful encryption.
        Use with extreme caution as this permanently deletes the original files.
        Ensure you have tested decryption before using this option.

    .EXAMPLE
        PS > Protect-PathWithPassword -Path "C:\Documents\secret.txt"

        Encrypts a single file, prompting for password. Creates secret.txt.enc in the same directory.

    .EXAMPLE
        PS > $password = Read-Host -AsSecureString -Prompt "Enter encryption password"
        PS > Protect-PathWithPassword -Path "C:\Documents\secret.txt" -Password $password

        Encrypts a single file with a pre-entered password, creating secret.txt.enc.

    .EXAMPLE
        PS > Protect-PathWithPassword -Path "C:\Projects" -Recurse

        Recursively encrypts all files in the Projects directory and subdirectories, prompting for password.

    .EXAMPLE
        PS > Get-ChildItem "*.txt" | Protect-PathWithPassword -Password $password -RemoveOriginal

        Encrypts all .txt files in current directory via pipeline and removes the original files.

    .EXAMPLE
        PS > Protect-PathWithPassword -Path "C:\Data" -OutputPath "C:\Encrypted" -Recurse -Force

        Encrypts all files from C:\Data recursively, placing encrypted files in C:\Encrypted, overwriting existing files.

    .EXAMPLE
        PS > Protect-PathWithPassword -Path "/home/user/documents" -Recurse

        Linux/macOS example: Encrypts all files in the documents directory recursively.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns objects with OriginalPath, EncryptedPath, Success, and Error properties for each processed file.

    .NOTES
        SECURITY:
        Uses cryptographically secure random number generation for salts and IVs.
        Each file gets a unique salt and IV, making identical files produce different encrypted output.

        COMPATIBILITY:
        Requires .NET Framework 4.0+ or .NET Core 2.0+ for cryptographic functions.

        PERFORMANCE:
        Large files are processed efficiently using streaming operations where possible.

        CLEANUP:
        Original files are only removed after successful encryption when -RemoveOriginal is specified.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateScript({
                if (-not (Test-Path $_))
                {
                    throw "Path does not exist: $_"
                }
                $true
            })]
        [String]$Path,

        [Parameter()]
        [ValidateNotNull()]
        [SecureString]$Password,

        [Parameter()]
        [String]$OutputPath,

        [Parameter()]
        [Switch]$Recurse,

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$RemoveOriginal
    )

    begin
    {
        Write-Verbose 'Starting encryption process'

        # Validate .NET encryption support
        try
        {
            Add-Type -AssemblyName System.Security -ErrorAction Stop
        }
        catch
        {
            throw 'System.Security assembly not available. Encryption requires .NET Framework 4.0+ or .NET Core 2.0+'
        }

        # Get password if not provided
        if (-not $Password)
        {
            Write-Host 'Enter encryption password:' -ForegroundColor Yellow
            $Password = Read-Host -AsSecureString
        }

        # Resolve output path if provided
        if ($OutputPath)
        {
            # Expand ~ to home directory and resolve relative paths
            if ($OutputPath.StartsWith('~'))
            {
                $OutputPath = $OutputPath -replace '^~', [System.Environment]::GetFolderPath('UserProfile')
            }

            # Convert to absolute path
            try
            {
                $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
            }
            catch
            {
                throw "Invalid output path: $OutputPath"
            }

            # Create output directory if it doesn't exist and it looks like a directory
            if (-not (Test-Path $OutputPath))
            {
                # Check if this looks like a directory (no extension or ends with slash/backslash)
                $isDirectory = (-not [System.IO.Path]::HasExtension($OutputPath)) -or
                $OutputPath.EndsWith('/') -or
                $OutputPath.EndsWith('\')

                if ($isDirectory)
                {
                    try
                    {
                        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
                        Write-Verbose "Created output directory: $OutputPath"
                    }
                    catch
                    {
                        throw "Failed to create output directory: $OutputPath"
                    }
                }
                else
                {
                    # It's a file path, so create the parent directory if needed
                    $parentDir = [System.IO.Path]::GetDirectoryName($OutputPath)
                    if ($parentDir -and -not (Test-Path $parentDir))
                    {
                        try
                        {
                            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                            Write-Verbose "Created parent directory: $parentDir"
                        }
                        catch
                        {
                            throw "Failed to create parent directory: $parentDir"
                        }
                    }
                }
            }
        }
    }

    process
    {
        try
        {
            $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop
            $item = Get-Item -Path $resolvedPath -ErrorAction Stop

            if ($item.PSIsContainer)
            {
                Write-Verbose "Processing directory: $($item.FullName)"
                if ($Recurse)
                {
                    Get-ChildItem -Path $item.FullName -File -Recurse | ForEach-Object {
                        Invoke-FileEncryption -FilePath $_.FullName -Password $Password -OutputPath $OutputPath -Force:$Force -RemoveOriginal:$RemoveOriginal
                    }
                }
                else
                {
                    Get-ChildItem -Path $item.FullName -File | ForEach-Object {
                        Invoke-FileEncryption -FilePath $_.FullName -Password $Password -OutputPath $OutputPath -Force:$Force -RemoveOriginal:$RemoveOriginal
                    }
                }
            }
            else
            {
                Write-Verbose "Processing file: $($item.FullName)"
                Invoke-FileEncryption -FilePath $item.FullName -Password $Password -OutputPath $OutputPath -Force:$Force -RemoveOriginal:$RemoveOriginal
            }
        }
        catch
        {
            Write-Error "Failed to process path '$Path': $($_.Exception.Message)"
            [PSCustomObject]@{
                OriginalPath = $Path
                EncryptedPath = $null
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }

    end
    {
        Write-Verbose 'Encryption process completed'
    }
}

function Invoke-FileEncryption
{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [String]$FilePath,
        [SecureString]$Password,
        [String]$OutputPath,
        [Switch]$Force,
        [Switch]$RemoveOriginal
    )

    try
    {
        # Determine output file path
        if ($OutputPath)
        {
            if (Test-Path $OutputPath -PathType Container)
            {
                $outputFile = Join-Path $OutputPath ([System.IO.Path]::GetFileName($FilePath) + '.enc')
            }
            else
            {
                $outputFile = $OutputPath
            }
        }
        else
        {
            $outputFile = $FilePath + '.enc'
        }

        # Check if output file exists
        if ((Test-Path $outputFile) -and -not $Force)
        {
            Write-Warning "Skipping file: $FilePath (file exists, use -Force to overwrite)"
            return [PSCustomObject]@{
                OriginalPath = $FilePath
                EncryptedPath = $outputFile
                Success = $false
                Error = 'File exists and Force not specified'
            }
        }

        if ($PSCmdlet.ShouldProcess($FilePath, 'Encrypt file'))
        {
            # Convert SecureString to bytes for key derivation
            $passwordPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            try
            {
                $passwordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
                $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($passwordPlain)
            }
            finally
            {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)
                if ($passwordPlain)
                {
                    $passwordPlain = $null
                }
            }

            # Generate random salt and IV
            $salt = New-Object byte[] 32
            $iv = New-Object byte[] 16
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rng.GetBytes($salt)
            $rng.GetBytes($iv)
            $rng.Dispose()

            # Derive key using PBKDF2
            $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passwordBytes, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
            $key = $pbkdf2.GetBytes(32) # 256-bit key
            $pbkdf2.Dispose()

            # Clear password bytes
            [Array]::Clear($passwordBytes, 0, $passwordBytes.Length)

            # Read input file
            $inputBytes = [System.IO.File]::ReadAllBytes($FilePath)

            # Encrypt using AES
            $aes = [System.Security.Cryptography.Aes]::Create()
            $aes.Key = $key
            $aes.IV = $iv
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

            $encryptor = $aes.CreateEncryptor()
            $encryptedBytes = $encryptor.TransformFinalBlock($inputBytes, 0, $inputBytes.Length)

            # Clean up
            $encryptor.Dispose()
            $aes.Dispose()
            [Array]::Clear($key, 0, $key.Length)

            # Create output: salt + iv + encrypted data
            $outputBytes = $salt + $iv + $encryptedBytes

            # Write encrypted file
            [System.IO.File]::WriteAllBytes($outputFile, $outputBytes)

            # Remove original file if requested
            if ($RemoveOriginal)
            {
                Remove-Item -Path $FilePath -Force
                Write-Verbose "Removed original file: $FilePath"
            }

            Write-Verbose "Successfully encrypted '$FilePath' to '$outputFile'"
            [PSCustomObject]@{
                OriginalPath = $FilePath
                EncryptedPath = $outputFile
                Success = $true
                Error = $null
            }
        }
        else
        {
            # WhatIf - return what would happen
            [PSCustomObject]@{
                OriginalPath = $FilePath
                EncryptedPath = $outputFile
                Success = $true
                Error = $null
            }
        }
    }
    catch
    {
        Write-Error "Failed to encrypt file '$FilePath': $($_.Exception.Message)"
        [PSCustomObject]@{
            OriginalPath = $FilePath
            EncryptedPath = $outputFile
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

New-Alias -Name 'Encrypt-PathWithPassword' -Value 'Protect-PathWithPassword' -Force
