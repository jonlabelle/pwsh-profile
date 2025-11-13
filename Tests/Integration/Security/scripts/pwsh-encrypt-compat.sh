#!/usr/bin/env bash
#
# OpenSSL-compatible encryption/decryption for PowerShell Protect-PathWithPassword format
#
# WHY THIS SCRIPT EXISTS:
# PowerShell's Protect-PathWithPassword and Unprotect-PathWithPassword functions use a specific
# file format that differs from OpenSSL's standard 'enc' command. This script bridges that gap,
# allowing encryption/decryption on systems where PowerShell may not be available (or practical).
#
# WHEN TO USE THIS:
# - Encrypting files on Linux/Unix servers without PowerShell
# - Decrypting PowerShell-encrypted files in bash scripts or CI/CD pipelines
# - Creating encrypted files that need to be decrypted by PowerShell on Windows
# - Automating encryption tasks in environments where bash is preferred over PowerShell
#
# WHAT MAKES IT COMPATIBLE:
# This script replicates PowerShell's exact encryption approach:
# - File format: [32-byte salt][16-byte IV][AES-256-CBC encrypted data]
# - Key derivation: PBKDF2-HMAC-SHA256 with 100,000 iterations (same as PowerShell)
# - Uses OpenSSL's 'kdf' command (3.0+) for key derivation
# - Uses OpenSSL's 'enc' with explicit -K (key) and -iv flags for encryption
#
# NOTE: This is NOT the same as 'openssl enc -aes-256-cbc -pbkdf2' which uses a different
# file format (Salted__ header + 8-byte salt + derived IV). This script uses a separate
# 32-byte salt and explicit 16-byte IV to match PowerShell's implementation.
#
# shellcheck disable=SC2155

set -e

SCRIPT_NAME=$(basename "$0")

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <encrypt|decrypt> -i <input> -o <output> [-p <password>]

Encrypt or decrypt files using the same format as PowerShell's Protect-PathWithPassword.

Options:
    encrypt         Encrypt the input file
    decrypt         Decrypt the input file
    -i <input>      Input file path
    -o <output>     Output file path
    -p <password>   Password (if not provided, will prompt)

Examples:
    # Encrypt a file
    $SCRIPT_NAME encrypt -i secret.txt -o secret.txt.enc -p "MyPassword123"

    # Decrypt a file
    $SCRIPT_NAME decrypt -i secret.txt.enc -o secret.txt -p "MyPassword123"

    # Encrypt without password in command (prompts securely)
    $SCRIPT_NAME encrypt -i secret.txt -o secret.txt.enc

EOF
  exit 1
}

# Check dependencies
check_dependencies() {
  local missing=()
  for cmd in openssl xxd; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo "Error: Missing required commands: ${missing[*]}" >&2
    echo "Please install: ${missing[*]}" >&2
    exit 1
  fi
}

# Derive key using PBKDF2-HMAC-SHA256
derive_key() {
  local password="$1"
  local salt_hex="$2"
  local iterations=100000

  # Convert password to hex
  local password_hex=$(echo -n "$password" | xxd -p -c 256 | tr -d '\n')

  # Use OpenSSL to derive the key
  openssl kdf -binary -keylen 32 \
    -kdfopt digest:SHA256 \
    -kdfopt hexpass:"$password_hex" \
    -kdfopt hexsalt:"$salt_hex" \
    -kdfopt iter:$iterations \
    PBKDF2 2>/dev/null | xxd -p -c 256 | tr -d '\n'
}

encrypt_file() {
  local input="$1"
  local output="$2"
  local password="$3"

  # Generate random 32-byte salt and 16-byte IV
  local salt_hex=$(openssl rand -hex 32)
  local iv_hex=$(openssl rand -hex 16)

  echo "Generating random salt and IV..." >&2

  # Derive key using PBKDF2
  echo "Deriving encryption key using PBKDF2-HMAC-SHA256 (100,000 iterations)..." >&2
  local key_hex=$(derive_key "$password" "$salt_hex")

  if [ -z "$key_hex" ]; then
    echo "Error: Failed to derive encryption key" >&2
    exit 1
  fi

  # Encrypt the file using AES-256-CBC
  echo "Encrypting file..." >&2
  local encrypted_hex=$(openssl enc -aes-256-cbc -in "$input" -K "$key_hex" -iv "$iv_hex" -e | xxd -p -c 256 | tr -d '\n')

  # Combine: salt (32 bytes) + IV (16 bytes) + encrypted data
  echo -n "${salt_hex}${iv_hex}${encrypted_hex}" | xxd -r -p >"$output"

  echo "Successfully encrypted '$input' -> '$output'" >&2
  echo "File size: $(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null) bytes" >&2
}

decrypt_file() {
  local input="$1"
  local output="$2"
  local password="$3"

  # Read the encrypted file
  local file_hex=$(xxd -p -c 256 "$input" | tr -d '\n')
  local file_size=$((${#file_hex} / 2))

  echo "Reading encrypted file (${file_size} bytes)..." >&2

  # Validate minimum file size (32 + 16 + at least 16 bytes of encrypted data)
  if [ $file_size -lt 64 ]; then
    echo "Error: File too small to be valid encrypted file (minimum 64 bytes)" >&2
    exit 1
  fi

  # Extract salt (first 32 bytes = 64 hex chars)
  local salt_hex="${file_hex:0:64}"

  # Extract IV (next 16 bytes = 32 hex chars)
  local iv_hex="${file_hex:64:32}"

  # Extract encrypted data (remainder)
  local encrypted_hex="${file_hex:96}"

  echo "Extracting salt and IV..." >&2

  # Derive key using PBKDF2
  echo "Deriving decryption key using PBKDF2-HMAC-SHA256 (100,000 iterations)..." >&2
  local key_hex=$(derive_key "$password" "$salt_hex")

  if [ -z "$key_hex" ]; then
    echo "Error: Failed to derive decryption key" >&2
    exit 1
  fi

  # Decrypt the data
  echo "Decrypting file..." >&2
  if ! echo -n "$encrypted_hex" | xxd -r -p | openssl enc -aes-256-cbc -d -K "$key_hex" -iv "$iv_hex" >"$output" 2>/dev/null; then
    echo "Error: Decryption failed. Invalid password or corrupted file." >&2
    rm -f "$output"
    exit 1
  fi

  echo "Successfully decrypted '$input' -> '$output'" >&2
  echo "File size: $(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null) bytes" >&2
}

# Parse arguments
ACTION=""
INPUT=""
OUTPUT=""
PASSWORD=""

if [ $# -eq 0 ]; then
  usage
fi

ACTION="$1"
shift

if [ "$ACTION" != "encrypt" ] && [ "$ACTION" != "decrypt" ]; then
  echo "Error: First argument must be 'encrypt' or 'decrypt'" >&2
  usage
fi

while [ $# -gt 0 ]; do
  case "$1" in
  -i)
    INPUT="$2"
    shift 2
    ;;
  -o)
    OUTPUT="$2"
    shift 2
    ;;
  -p)
    PASSWORD="$2"
    shift 2
    ;;
  *)
    echo "Error: Unknown option: $1" >&2
    usage
    ;;
  esac
done

# Validate required arguments
if [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
  echo "Error: Both -i (input) and -o (output) are required" >&2
  usage
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: Input file not found: $INPUT" >&2
  exit 1
fi

# Prompt for password if not provided
if [ -z "$PASSWORD" ]; then
  echo -n "Enter password: " >&2
  read -r -s PASSWORD
  echo >&2
  if [ -z "$PASSWORD" ]; then
    echo "Error: Password cannot be empty" >&2
    exit 1
  fi
fi

# Check dependencies
check_dependencies

# Perform action
if [ "$ACTION" = "encrypt" ]; then
  encrypt_file "$INPUT" "$OUTPUT" "$PASSWORD"
else
  decrypt_file "$INPUT" "$OUTPUT" "$PASSWORD"
fi
