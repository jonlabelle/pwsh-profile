FROM mcr.microsoft.com/powershell:lts-alpine-3.20

# Install required tools for tests
# - rsync: Required by Sync-Directory function
# - git: Required by Remove-GitIgnoredFiles and install.ps1 tests
# - xdotool: Required by Start-KeepAlive function on Linux (optional but enables full test coverage)
# - openssl: Required for some cryptography-related tests
# - bash: Some test scripts may require bash shell
RUN apk add --no-cache \
  rsync \
  git \
  xdotool \
  openssl \
  bash

# Set working directory
WORKDIR /workspace

# Copy dependency installation script and configuration files
COPY dev-requirements.ps1 /tmp/
COPY PSScriptAnalyzerSettings.psd1 /tmp/

# Install PowerShell test dependencies
RUN pwsh -NoProfile -File /tmp/dev-requirements.ps1 && \
  rm -rf /tmp/dev-requirements.ps1 /tmp/PSScriptAnalyzerSettings.psd1

# Disable PowerShell telemetry
ENV POWERSHELL_TELEMETRY_OPTOUT=1
ENV DISABLE_TELEMETRY=1

# Default command
CMD ["pwsh"]
