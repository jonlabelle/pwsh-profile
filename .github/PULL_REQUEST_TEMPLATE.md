## Summary

<!-- Brief description of what this PR adds, changes, or fixes -->

## Type of Change

- [ ] New function
- [ ] Bug fix
- [ ] Enhancement to existing function
- [ ] Tests / CI
- [ ] Documentation

## Checklist

- [ ] Follows `Verb-Noun.ps1` naming convention and standard function structure
- [ ] Compatible with PowerShell Desktop 5.1 and Core 6.2+
- [ ] No Windows-only APIs used (for example `Resolve-DnsName`) unless platform-gated
- [ ] Files with Unicode characters are saved as UTF-8 with BOM
- [ ] PSScriptAnalyzer passes with zero errors
- [ ] Unit/integration tests added or updated
- [ ] Tests include `$Global:ProgressPreference = 'SilentlyContinue'` in `BeforeAll`
