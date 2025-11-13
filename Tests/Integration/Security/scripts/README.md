# PowerShell Encryption Compatibility Scripts

This directory contains scripts that provide interoperability with PowerShell's `Protect-PathWithPassword` and `Unprotect-PathWithPassword` functions using standard Unix/Linux tools.

## pwsh-encrypt-compat.sh

A bash script that encrypts and decrypts files using the same format as PowerShell's password-based encryption functions.

### Features

- **Full compatibility** with `Protect-PathWithPassword` and `Unprotect-PathWithPassword`
- **Same cryptographic parameters**: AES-256-CBC with PBKDF2-HMAC-SHA256 (100,000 iterations)
- **Same file format**: `[32-byte salt][16-byte IV][encrypted data]`
- Works on any system with OpenSSL 3.0+ and bash

### Requirements

- **OpenSSL 3.0+** with KDF support
- **bash** (any modern version)
- **xxd** (usually included with vim)

### Usage

```bash
# Encrypt a file
./Tests/Integration/Security/scripts/pwsh-encrypt-compat.sh encrypt -i secret.txt -o secret.txt.enc -p "MyPassword123"

# Decrypt a file
./Tests/Integration/Security/scripts/pwsh-encrypt-compat.sh decrypt -i secret.txt.enc -o secret.txt -p "MyPassword123"

# Prompt for password (more secure)
./Tests/Integration/Security/scripts/pwsh-encrypt-compat.sh encrypt -i secret.txt -o secret.txt.enc

# Get help
./Tests/Integration/Security/scripts/pwsh-encrypt-compat.sh
```

### Cross-Platform Workflow Examples

#### Encrypt on Linux, Decrypt on Windows with PowerShell

```bash
# On Linux:
./Tests/Integration/Security/scripts/pwsh-encrypt-compat.sh encrypt -i document.pdf -o document.pdf.enc

# Transfer document.pdf.enc to Windows, then in PowerShell:
Unprotect-PathWithPassword -Path "C:\Downloads\document.pdf.enc"
```

#### Encrypt on Windows with PowerShell, Decrypt on macOS with Bash

```powershell
# On Windows PowerShell:
Protect-PathWithPassword -Path "C:\Data\report.xlsx" -OutputPath "C:\Share\report.xlsx.enc"

# Transfer to macOS, then in bash:
./Tests/Integration/Security/scripts/pwsh-encrypt-compat.sh decrypt -i ~/Downloads/report.xlsx.enc -o ~/Documents/report.xlsx
```

### Technical Details

The script uses OpenSSL's lower-level commands to exactly replicate PowerShell's encryption:

1. **Key Derivation**: `openssl kdf` with PBKDF2, SHA-256, 100,000 iterations
2. **Encryption**: `openssl enc` with AES-256-CBC using explicit key (`-K`) and IV (`-iv`)
3. **File Format**: Binary concatenation of salt + IV + ciphertext

This differs from OpenSSL's standard `enc` command which uses its own `Salted__` format.

### Verification

Compatibility is tested in the integration test suite:

```bash
pwsh -NoProfile -File ./Invoke-Tests.ps1 -TestType Integration
```

The tests verify:

- Files encrypted by bash can be decrypted by PowerShell
- Files encrypted by PowerShell can be decrypted by bash
- Binary file integrity is preserved
- All platforms produce identical results

### Limitations

- **OpenSSL 3.0+ required**: Older OpenSSL versions don't have the `kdf` command
- **Not compatible** with OpenSSL's default `enc` command format
- **Text files only** in password prompt mode (binary passwords not supported in interactive mode)

### Security Notes

- Uses cryptographically secure random generation for salts and IVs (via `openssl rand`)
- Each encrypted file gets a unique salt and IV (identical files produce different output)
- 100,000 PBKDF2 iterations provide strong protection against brute-force attacks
- No password is stored; only used transiently for key derivation
