function Get-StringHash
{
    <#
    .SYNOPSIS
        Computes the hash value for arbitrary string input using a specified hash algorithm.

    .DESCRIPTION
        The Get-StringHash function calculates hash values for strings or other input data using
        various cryptographic hash algorithms. This provides similar functionality to Get-FileHash
        but for arbitrary values rather than files.

        Supports the same hash algorithms as Get-FileHash:
        - SHA1
        - SHA256 (default)
        - SHA384
        - SHA512
        - MD5

        The function is cross-platform compatible and works on PowerShell 5.1+ and PowerShell Core 6.2+.

    .PARAMETER InputObject
        The string or object to hash. If an object is provided, it will be converted to a string
        using its ToString() method. Supports pipeline input.

    .PARAMETER Algorithm
        Specifies the cryptographic hash algorithm to use. Valid values are SHA1, SHA256, SHA384,
        SHA512, and MD5. Default is SHA256.

    .PARAMETER Encoding
        Specifies the character encoding to use when converting the input string to bytes.
        Valid values are ASCII, UTF7, UTF8, UTF32, Unicode, BigEndianUnicode, and Default.
        Default is UTF8.

    .EXAMPLE
        PS > Get-StringHash -InputObject 'Hello, World!'

        Algorithm Hash                                                                   InputObject
        --------- ----                                                                   -----------
        SHA256    DFFD6021BB2BD5B0AF676290809EC3A53191DD81C7F70A4B28688A362182986F Hello, World!

        Computes the SHA256 hash (default algorithm) of the string 'Hello, World!'.

    .EXAMPLE
        PS > 'PowerShell' | Get-StringHash -Algorithm MD5

        Algorithm Hash                             InputObject
        --------- ----                             -----------
        MD5       3D265B4E1EEEF0DDF17881FA003B18CC PowerShell

        Computes the MD5 hash of 'PowerShell' via pipeline input.

    .EXAMPLE
        PS > Get-StringHash -InputObject 'Test123' -Algorithm SHA512

        Algorithm Hash                                                                                                                             InputObject
        --------- ----                                                                                                                             -----------
        SHA512    C12834F1031F6497214F27D4432F26517AD494156CB88D512BDB1DC4B57DB2D692A3DFA269A19B0A0A2A0FD7D6A2A885E33C839C93C206DA30A187392847ED27 Test123

        Computes the SHA512 hash of 'Test123'.

    .EXAMPLE
        PS > Get-StringHash -InputObject 'Secret' -Algorithm SHA1

        Algorithm Hash                                     InputObject
        --------- ----                                     -----------
        SHA1      F4E7A8740DB0B7A0BFD8E63077261475F61FC2A6 Secret

        Computes the SHA1 hash of 'Secret'.

    .EXAMPLE
        PS > Get-StringHash -InputObject 'Encoding Test' -Encoding ASCII

        Algorithm Hash                                                             InputObject
        --------- ----                                                             -----------
        SHA256    1DB46F18A61A0FC83A2D0DC6FE962857821829AD04C82573A258D3CB3E395B36 Encoding Test

        Computes the SHA256 hash using ASCII encoding instead of the default UTF8.

    .EXAMPLE
        PS > 'password1', 'password2', 'password3' | Get-StringHash -Algorithm SHA256

        Algorithm Hash                                                             InputObject
        --------- ----                                                             -----------
        SHA256    0B14D501A594442A01C6859541BCB3E8164D183D32937B851835442F69D5C94E password1
        SHA256    6CF615D5BCAAC778352A8F1F3360D23F02F34EC182E259897FD6CE485D7870D4 password2
        SHA256    5906AC361A137E2D286465CD6588EBB5AC3F5AE955001100BC41577C3D751764 password3

        Computes SHA256 hashes for multiple strings via pipeline.

    .EXAMPLE
        PS > $result = Get-StringHash -InputObject 'MyData' -Algorithm SHA256
        PS > $result.Hash
        E5F0BD66F256CD1DE4A7DD743AD2DAA16EF94FCC0B4C4D6A9B54EEA78E9B2DF5

        Stores the result and accesses the Hash property directly.

    .EXAMPLE
        PS > Invoke-WebRequest -Uri $releaseUrl -OutFile './download.zip'
        PS > (Get-StringHash -InputObject (Get-Content ./download.zip -Raw) -Algorithm SHA512).Hash
        8A7E...

        Verifies the SHA512 checksum of a downloaded release artifact without needing external tools.

    .EXAMPLE
        PS > $hash = Get-StringHash -InputObject (Get-Content ./config.json -Raw)
        PS > $cacheKey = "config::" + $hash.Hash.Substring(0, 12)

        Generates a deterministic cache key or version token based on the contents of a configuration file.

    .OUTPUTS
        PSCustomObject
        Returns an object with the following properties:
        - Algorithm: The hash algorithm used
        - Hash: The computed hash value in hexadecimal format
        - InputObject: The original input string

    .NOTES
        The function uses .NET cryptographic classes for hash computation, ensuring cross-platform
        compatibility. Hash values are returned in uppercase hexadecimal format to match the
        behavior of Get-FileHash.

        Author: Jon LaBelle
        License: MIT
        Source: https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Utilities/Get-StringHash.ps1

    .LINK
        Get-FileHash
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [Object]$InputObject,

        [Parameter()]
        [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MD5')]
        [String]$Algorithm = 'SHA256',

        [Parameter()]
        [ValidateSet('ASCII', 'UTF7', 'UTF8', 'UTF32', 'Unicode', 'BigEndianUnicode', 'Default')]
        [String]$Encoding = 'UTF8'
    )

    begin
    {
        Write-Verbose "Initializing hash algorithm: $Algorithm"
        Write-Verbose "Using encoding: $Encoding"
    }

    process
    {
        try
        {
            # Convert input object to string
            $inputString = if ($null -eq $InputObject)
            {
                ''
            }
            elseif ($InputObject -is [String])
            {
                $InputObject
            }
            else
            {
                $InputObject.ToString()
            }

            Write-Verbose "Processing input: '$inputString'"

            # Get the appropriate text encoding
            $textEncoding = switch ($Encoding)
            {
                'ASCII' { [System.Text.Encoding]::ASCII }
                'UTF7' { [System.Text.Encoding]::UTF7 }
                'UTF8' { [System.Text.Encoding]::UTF8 }
                'UTF32' { [System.Text.Encoding]::UTF32 }
                'Unicode' { [System.Text.Encoding]::Unicode }
                'BigEndianUnicode' { [System.Text.Encoding]::BigEndianUnicode }
                'Default' { [System.Text.Encoding]::Default }
            }

            # Convert string to bytes using the specified encoding
            $inputBytes = $textEncoding.GetBytes($inputString)

            # Create the hash algorithm
            $hashAlgorithm = switch ($Algorithm)
            {
                'SHA1' { [System.Security.Cryptography.SHA1]::Create() }
                'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
                'SHA384' { [System.Security.Cryptography.SHA384]::Create() }
                'SHA512' { [System.Security.Cryptography.SHA512]::Create() }
                'MD5' { [System.Security.Cryptography.MD5]::Create() }
            }

            try
            {
                # Compute the hash
                $hashBytes = $hashAlgorithm.ComputeHash($inputBytes)

                # Convert hash bytes to hexadecimal string
                $hashString = ($hashBytes | ForEach-Object { $_.ToString('X2') }) -join ''

                Write-Verbose "Computed $Algorithm hash: $hashString"

                # Return result object
                [PSCustomObject]@{
                    Algorithm = $Algorithm
                    Hash = $hashString
                    InputObject = $inputString
                }
            }
            finally
            {
                # Dispose of the hash algorithm
                if ($hashAlgorithm)
                {
                    $hashAlgorithm.Dispose()
                }
            }
        }
        catch
        {
            Write-Error "Failed to compute hash: $_"
            throw
        }
    }

    end
    {
        Write-Verbose 'Hash computation completed'
    }
}
