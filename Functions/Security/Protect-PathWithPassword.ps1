function Protect-PathWithPassword
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
        - Encrypted data includes 8-byte magic header 'PWDPROT1' for password validation

        CROSS-PLATFORM COMPATIBILITY:
        This function works on PowerShell 5.1+ across Windows, macOS, and Linux
        by using .NET cryptographic classes instead of platform-specific APIs.

        ALIASES:
        The 'encrypt' alias is created only if it doesn't already exist in the current environment.

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

    .EXAMPLE
        # Cross-platform workflow: Encrypt on Windows, decrypt on Linux/macOS
        # On Windows:
        PS > Protect-PathWithPassword -Path "C:\data\secret.txt" -OutputPath "C:\share\secret.txt.enc"

        # Transfer secret.txt.enc to Linux/macOS, then decrypt:
        PS > Unprotect-PathWithPassword -Path "/mnt/share/secret.txt.enc"

        Files encrypted by this function can be decrypted on any platform running PowerShell 5.1+.

    .EXAMPLE
        # OpenSSL-compatible encryption (bash/zsh) - requires OpenSSL 3.0+ with KDF support:
        ./Tests/Integration/Security/scripts/pwsh-encrypt-compat.sh encrypt -i secret.txt -o secret.txt.enc -p "MyPassword123"

        # Files encrypted with the pwsh-encrypt-compat.sh script can be decrypted by PowerShell:
        PS > Unprotect-PathWithPassword -Path "secret.txt.enc"

        See Tests/Integration/Security/scripts/pwsh-encrypt-compat.sh for a bash implementation using OpenSSL that creates
        compatible encrypted files.

    .EXAMPLE
        PS > $password = ConvertTo-SecureString $env:BUILD_SECRET -AsPlainText -Force
        PS > Compress-Archive -Path './dist/*' -DestinationPath './artifacts/app.zip'
        PS > Protect-PathWithPassword -Path './artifacts/app.zip' -Password $password -OutputPath './artifacts/app.zip.enc' -RemoveOriginal

        CI/CD pipeline example: packages build output, encrypts it with a secret pulled from the environment, and deletes the plain artifact before publishing.

    .EXAMPLE
        PS > $password = Read-Host -AsSecureString -Prompt 'Enter vault password'
        PS > Get-ChildItem ./config/*.env | Protect-PathWithPassword -Password $password -OutputPath './secure-config' -Force

        Bulk-encrypts multiple configuration files into a secure directory, overwriting any existing encrypted copies.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns objects with OriginalPath, EncryptedPath, Success, and Error properties for each processed file.

    .NOTES
        SECURITY:
        Uses cryptographically secure random number generation for salts and IVs.
        Each file gets a unique salt and IV, making identical files produce different encrypted output.

        COMPATIBILITY:
        Requires .NET Framework 4.0+ or .NET Core 2.0+ for cryptographic functions.
        Files can be encrypted on one platform and decrypted on another (Windows/macOS/Linux).

        OPENSSL COMPATIBILITY:
        OpenSSL's 'enc' command uses a different file format and is NOT directly compatible.
        However, you can use OpenSSL's lower-level commands to create compatible files.

        A reference bash script (Tests/Integration/Security/scripts/pwsh-encrypt-compat.sh) is provided that uses
        OpenSSL's 'kdf' and 'enc' commands to create files compatible with these functions.
        The script uses: OpenSSL KDF for PBKDF2, explicit key (-K) and IV (-iv) for AES-256-CBC.

        Requirements: OpenSSL 3.0+ with KDF support, xxd (for hex conversion)

        PERFORMANCE:
        Large files are processed efficiently using streaming operations where possible.

        CLEANUP:
        Original files are only removed after successful encryption when -RemoveOriginal is specified.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Security/Protect-PathWithPassword.ps1
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

        # Internal helper function for file encryption
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
                    $initializationVector = New-Object byte[] 16
                    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
                    $rng.GetBytes($salt)
                    $rng.GetBytes($initializationVector)
                    $rng.Dispose()

                    # Derive key using PBKDF2
                    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passwordBytes, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
                    $key = $pbkdf2.GetBytes(32) # 256-bit key
                    $pbkdf2.Dispose()

                    # Clear password bytes
                    [Array]::Clear($passwordBytes, 0, $passwordBytes.Length)

                    # Read input file
                    $inputBytes = [System.IO.File]::ReadAllBytes($FilePath)

                    # Add magic header for password validation (8 bytes: PWDPROT1)
                    $magicHeader = [System.Text.Encoding]::ASCII.GetBytes('PWDPROT1')
                    $dataToEncrypt = New-Object byte[] ($magicHeader.Length + $inputBytes.Length)
                    [System.Buffer]::BlockCopy($magicHeader, 0, $dataToEncrypt, 0, $magicHeader.Length)
                    [System.Buffer]::BlockCopy($inputBytes, 0, $dataToEncrypt, $magicHeader.Length, $inputBytes.Length)

                    # Encrypt using AES
                    $aes = [System.Security.Cryptography.Aes]::Create()
                    $aes.Key = $key
                    $aes.IV = $initializationVector
                    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

                    $encryptor = $aes.CreateEncryptor()
                    $encryptedBytes = $encryptor.TransformFinalBlock($dataToEncrypt, 0, $dataToEncrypt.Length)

                    # Clean up
                    $encryptor.Dispose()
                    $aes.Dispose()
                    [Array]::Clear($key, 0, $key.Length)

                    # Create output: salt + iv + encrypted data
                    $outputBytes = $salt + $initializationVector + $encryptedBytes

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

# Create 'encrypt' alias only if it doesn't already exist
if (-not (Get-Command -Name 'encrypt' -ErrorAction SilentlyContinue))
{
    try
    {
        Write-Verbose "Creating 'encrypt' alias for Protect-PathWithPassword"
        Set-Alias -Name 'encrypt' -Value 'Protect-PathWithPassword' -Force -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Protect-PathWithPassword: Could not create 'encrypt' alias: $($_.Exception.Message)"
    }
}
