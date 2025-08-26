Integration tests for network/TLS functions.

These tests are executed by the `integration` job in GitHub Actions and may require network access. They are tagged with the 'Integration' tag so unit runs exclude them.

To run locally:

pwsh -NoProfile -Command "Import-Module Pester; Invoke-Pester -Path Tests -Tag Integration"
