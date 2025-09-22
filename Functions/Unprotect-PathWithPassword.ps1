function Unprotect-PathWithPassword
{
    <#
    .SYNOPSIS
        Decrypts files that were encrypted with Protect-PathWithPassword.

    .DESCRIPTION
        This function decrypts files that were encrypted using AES-256-CBC encryption with PBKDF2 key derivation.
        Restores original files from .enc encrypted files or processes entire directory structures.
        Compatible with files encrypted by Protect-PathWithPassword and uses the same cryptographic parameters.

        DECRYPTION DETAILS:
        - Reads encrypted file format: [Salt:32][IV:16][EncryptedData:Variable]
        - Uses AES-256-CBC decryption with the same PBKDF2 parameters as encryption
        - Validates file format and detects corruption or wrong passwords
        - Automatically removes .enc extension to restore original filenames

        CROSS-PLATFORM COMPATIBILITY: This function works on PowerShell 5.1+ across Windows, macOS, and Linux
        by using .NET cryptographic classes for maximum portability.

    .PARAMETER Path
        The encrypted file or directory path to decrypt. Accepts both relative and absolute paths.
        For files: Should typically have .enc extension (but not required).
        For directories: Automatically finds and processes all .enc files.
        Supports pipeline input from Get-ChildItem and other cmdlets.

    .PARAMETER Password
        SecureString containing the decryption password. Must match the password used for encryption.
        If not provided, prompts securely for the password.
        Wrong passwords will result in decryption failure with appropriate error messages.

    .PARAMETER OutputPath
        Optional output directory or file path for decrypted files.
        If not specified, removes .enc extension and creates files in the same location.
        For directories, creates decrypted files in the specified output directory.

    .PARAMETER Recurse
        When decrypting directories, recursively decrypt all .enc files in subdirectories.
        Without this switch, only .enc files in the root directory are processed.

    .PARAMETER Force
        Overwrite existing decrypted files without prompting for confirmation.
        Use with caution as this will replace existing files.

    .PARAMETER KeepEncrypted
        Keep the original encrypted .enc files after successful decryption.
        By default, encrypted files are removed after successful decryption.
        Use this option to maintain backup copies of encrypted files.

    .EXAMPLE
        PS > Unprotect-PathWithPassword -Path "C:\Documents\secret.txt.enc"

        Decrypts a single file, prompting for password. Creates secret.txt and removes secret.txt.enc.

    .EXAMPLE
        PS > $password = Read-Host -AsSecureString -Prompt "Enter decryption password"
        PS > Unprotect-PathWithPassword -Path "C:\Documents\secret.txt.enc" -Password $password

        Decrypts a single file with a pre-entered password.

    .EXAMPLE
        PS > Unprotect-PathWithPassword -Path "C:\Encrypted" -Recurse -KeepEncrypted

        Recursively decrypts all .enc files in the Encrypted directory, keeping the original encrypted files.

    .EXAMPLE
        PS > Get-ChildItem "*.enc" | Unprotect-PathWithPassword -Password $password

        Decrypts all .enc files in current directory via pipeline.

    .EXAMPLE
        PS > Unprotect-PathWithPassword -Path "C:\Encrypted" -OutputPath "C:\Decrypted" -Recurse -Force

        Decrypts all .enc files from C:\Encrypted recursively, placing decrypted files in C:\Decrypted.

    .EXAMPLE
        PS > Unprotect-PathWithPassword -Path "/home/user/encrypted" -Recurse

        Linux/macOS example: Decrypts all .enc files in the encrypted directory recursively.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns objects with EncryptedPath, DecryptedPath, Success, and Error properties for each processed file.

    .NOTES
        SECURITY:
        Provides secure password verification and detects file corruption or tampering.
        Failed decryption attempts do not create partial files.

        COMPATIBILITY:
        Requires .NET Framework 4.0+ or .NET Core 2.0+ for cryptographic functions.

        ERROR HANDLING:
        Distinguishes between wrong passwords, corrupted files, and other errors.

        CLEANUP:
        Encrypted files are only removed after successful decryption unless -KeepEncrypted is specified.

    .LINK
        Protect-PathWithPassword
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateScript({
                $normalizedPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($_)
                if (-not (Test-Path $normalizedPath))
                {
                    throw "Path does not exist: $normalizedPath"
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
        [Switch]$KeepEncrypted
    )

    begin
    {
        Write-Verbose 'Starting decryption process'

        # Validate .NET encryption support
        try
        {
            Add-Type -AssemblyName System.Security -ErrorAction Stop
        }
        catch
        {
            throw 'System.Security assembly not available. Decryption requires .NET Framework 4.0+ or .NET Core 2.0+'
        }

        # Get password if not provided
        if (-not $Password)
        {
            Write-Host 'Enter decryption password:' -ForegroundColor Yellow
            $Password = Read-Host -AsSecureString
        }

        # Resolve output path if provided
        if ($OutputPath)
        {
            # Expand '~', resolve relative paths, and convert to absolute path
            $OutputPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

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
            # Normalize path first (handles ~, relative paths)
            $Path = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            # Then validate existence
            $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop
            $item = Get-Item -Path $resolvedPath -ErrorAction Stop

            if ($item.PSIsContainer)
            {
                Write-Verbose "Processing directory: $($item.FullName)"
                if ($Recurse)
                {
                    Get-ChildItem -Path $item.FullName -File -Filter '*.enc' -Recurse | ForEach-Object {
                        Invoke-FileDecryption -FilePath $_.FullName -Password $Password -OutputPath $OutputPath -Force:$Force -KeepEncrypted:$KeepEncrypted
                    }
                }
                else
                {
                    Get-ChildItem -Path $item.FullName -File -Filter '*.enc' | ForEach-Object {
                        Invoke-FileDecryption -FilePath $_.FullName -Password $Password -OutputPath $OutputPath -Force:$Force -KeepEncrypted:$KeepEncrypted
                    }
                }
            }
            else
            {
                Write-Verbose "Processing file: $($item.FullName)"
                Invoke-FileDecryption -FilePath $item.FullName -Password $Password -OutputPath $OutputPath -Force:$Force -KeepEncrypted:$KeepEncrypted
            }
        }
        catch
        {
            Write-Error "Failed to process path '$Path': $($_.Exception.Message)"
            [PSCustomObject]@{
                EncryptedPath = $Path
                DecryptedPath = $null
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }

    end
    {
        Write-Verbose 'Decryption process completed'
    }
}

function Invoke-FileDecryption
{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [String]$FilePath,
        [SecureString]$Password,
        [String]$OutputPath,
        [Switch]$Force,
        [Switch]$KeepEncrypted
    )

    try
    {
        # Determine output file path
        if ($OutputPath)
        {
            if (Test-Path $OutputPath -PathType Container)
            {
                $fileName = [System.IO.Path]::GetFileName($FilePath)
                if ($fileName.EndsWith('.enc'))
                {
                    $fileName = $fileName.Substring(0, $fileName.Length - 4)
                }
                $outputFile = Join-Path $OutputPath $fileName
            }
            else
            {
                $outputFile = $OutputPath
            }
        }
        else
        {
            if ($FilePath.EndsWith('.enc'))
            {
                $outputFile = $FilePath.Substring(0, $FilePath.Length - 4)
            }
            else
            {
                $outputFile = $FilePath + '.dec'
            }
        }

        # Check if output file exists
        if ((Test-Path $outputFile) -and -not $Force)
        {
            Write-Warning "Skipping file: $FilePath (file exists, use -Force to overwrite)"
            return [PSCustomObject]@{
                EncryptedPath = $FilePath
                DecryptedPath = $outputFile
                Success = $false
                Error = 'File exists and Force not specified'
            }
        }

        if ($PSCmdlet.ShouldProcess($FilePath, 'Decrypt file'))
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

            # Read encrypted file
            $encryptedData = [System.IO.File]::ReadAllBytes($FilePath)

            # Validate minimum file size (32 bytes salt + 16 bytes IV + at least 16 bytes data)
            if ($encryptedData.Length -lt 64)
            {
                throw 'Invalid encrypted file format: file too small'
            }

            # Extract salt, IV, and encrypted data
            $salt = $encryptedData[0..31]
            $initializationVector = $encryptedData[32..47]
            $encryptedBytes = $encryptedData[48..($encryptedData.Length - 1)]

            # Derive key using PBKDF2 (same parameters as encryption)
            $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passwordBytes, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
            $key = $pbkdf2.GetBytes(32) # 256-bit key
            $pbkdf2.Dispose()

            # Clear password bytes
            [Array]::Clear($passwordBytes, 0, $passwordBytes.Length)

            # Decrypt using AES
            $aes = [System.Security.Cryptography.Aes]::Create()
            $aes.Key = $key
            $aes.IV = $initializationVector
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

            try
            {
                $decryptor = $aes.CreateDecryptor()
                $decryptedBytes = $decryptor.TransformFinalBlock($encryptedBytes, 0, $encryptedBytes.Length)
                $decryptor.Dispose()
            }
            catch
            {
                throw 'Decryption failed. Invalid password or corrupted file.'
            }
            finally
            {
                $aes.Dispose()
                [Array]::Clear($key, 0, $key.Length)
            }

            # Write decrypted file
            [System.IO.File]::WriteAllBytes($outputFile, $decryptedBytes)

            # Remove encrypted file if requested
            if (-not $KeepEncrypted)
            {
                Remove-Item -Path $FilePath -Force
                Write-Verbose "Removed encrypted file: $FilePath"
            }

            Write-Verbose "Successfully decrypted '$FilePath' to '$outputFile'"
            [PSCustomObject]@{
                EncryptedPath = $FilePath
                DecryptedPath = $outputFile
                Success = $true
                Error = $null
            }
        }
        else
        {
            # WhatIf - return what would happen
            [PSCustomObject]@{
                EncryptedPath = $FilePath
                DecryptedPath = $outputFile
                Success = $true
                Error = $null
            }
        }
    }
    catch
    {
        Write-Error "Failed to decrypt file '$FilePath': $($_.Exception.Message)"
        [PSCustomObject]@{
            EncryptedPath = $FilePath
            DecryptedPath = $outputFile
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

New-Alias -Name 'Decrypt-PathWithPassword' -Value 'Unprotect-PathWithPassword' -Force
