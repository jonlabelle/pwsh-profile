BeforeAll {
    # Dot source the function
    . $PSScriptRoot/../../../Functions/Utilities/Replace-StringInFile.ps1

    # Import test cleanup utilities
    . $PSScriptRoot/../../TestCleanupUtilities.ps1
}

Describe 'Replace-StringInFile Integration Tests' -Tag 'Integration' {

    BeforeAll {
        # Create a test directory in the repository's tmp folder
        $tmpPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../tmp'
        $script:testRoot = Join-Path -Path $tmpPath -ChildPath "replace-string-integration-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null
    }

    AfterAll {
        # Clean up test directory
        if (Test-Path $script:testRoot)
        {
            Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Real-world Code Refactoring Scenarios' {
        It 'Should rename class names preserving case across multiple files' {
            # Create a mock C# project structure
            $srcDir = Join-Path $script:testRoot 'src'
            New-Item -ItemType Directory -Path $srcDir -Force | Out-Null

            $file1 = Join-Path $srcDir 'UserService.cs'
            $file2 = Join-Path $srcDir 'UserController.cs'
            $file3 = Join-Path $srcDir 'README.md'

            @'
public class UserService
{
    private readonly IUserRepository userRepository;

    public UserService(IUserRepository userRepository)
    {
        this.userRepository = userRepository;
    }
}
'@ | Set-Content -Path $file1 -NoNewline

            @'
// USER_SERVICE endpoint
public class UserController
{
    private readonly UserService userService;

    public UserController(UserService userService)
    {
        this.userService = userService;
    }
}
'@ | Set-Content -Path $file2 -NoNewline

            @'
# UserService Documentation

The UserService class provides user management functionality.
'@ | Set-Content -Path $file3 -NoNewline

            # Perform refactoring
            $files = Get-ChildItem -Path $srcDir -File
            $results = $files | Replace-StringInFile -OldString 'UserService' -NewString 'AccountService' -CaseInsensitive -PreserveCase

            # Verify results
            $content1 = Get-Content -Path $file1 -Raw
            $content1 | Should -Match 'public class AccountService'
            $content1 | Should -Match 'private readonly IUserRepository userRepository'  # Should not change
            $content1 | Should -Match 'public AccountService\(IUserRepository userRepository\)'

            $content2 = Get-Content -Path $file2 -Raw
            $content2 | Should -Match '// USER_SERVICE endpoint'  # Commented code not changed
            $content2 | Should -Match 'private readonly AccountService accountService'
            $content2 | Should -Match 'public UserController\(AccountService accountService\)'

            $content3 = Get-Content -Path $file3 -Raw
            $content3 | Should -Match '# AccountService Documentation'
            $content3 | Should -Match 'The AccountService class'

            # Verify all files were processed
            $results.Count | Should -Be 3
            ($results | Where-Object { $_.ReplacementsMade }).Count | Should -Be 3
        }

        It 'Should preserve camelCase and PascalCase in JavaScript code refactoring' {
            $jsFile = Join-Path $script:testRoot 'app.js'

            @'
const userName = getUserName();
const UserName = 'John';
function setUserName(newUserName) {
    this.userName = newUserName;
}
'@ | Set-Content -Path $jsFile -NoNewline

            $result = Replace-StringInFile -Path $jsFile -OldString 'username' -NewString 'accountid' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $jsFile -Raw
            $content | Should -Match 'const accountId = getAccountId\(\);'
            $content | Should -Match "const AccountId = 'John';"
            $content | Should -Match 'function setAccountId\(newAccountId\)'
            $content | Should -Match 'this\.accountId = newAccountId;'
            $result.MatchCount | Should -Be 7  # userName, getUserName, UserName, setUserName, newUserName (x2), userName
        }

        It 'Should update variable names in configuration files' {
            $configFile = Join-Path $script:testRoot 'app.config'

            @'
database_host=localhost
DATABASE_PORT=5432
Database_Name=myapp
database_user=admin
'@ | Set-Content -Path $configFile -NoNewline

            $result = Replace-StringInFile -Path $configFile -OldString 'database' -NewString 'postgres' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $configFile -Raw
            $content | Should -Match 'postgres_host=localhost'
            $content | Should -Match 'POSTGRES_PORT=5432'
            $content | Should -Match 'Postgres_Name=myapp'
            $content | Should -Match 'postgres_user=admin'
            $result.MatchCount | Should -Be 4
        }

        It 'Should handle multiple wildcard files with PreserveCase' {
            $docsDir = Join-Path $script:testRoot 'docs'
            New-Item -ItemType Directory -Path $docsDir -Force | Out-Null

            # Create multiple markdown files
            'OldProduct features' | Set-Content -Path (Join-Path $docsDir 'features.md') -NoNewline
            'OLDPRODUCT installation' | Set-Content -Path (Join-Path $docsDir 'install.md') -NoNewline
            'oldproduct configuration' | Set-Content -Path (Join-Path $docsDir 'config.md') -NoNewline

            # Replace across all files using wildcard
            $pattern = Join-Path $docsDir '*.md'
            $results = Replace-StringInFile -Path $pattern -OldString 'oldproduct' -NewString 'newproduct' -CaseInsensitive -PreserveCase

            # Verify each file
            Get-Content -Path (Join-Path $docsDir 'features.md') -Raw | Should -Be 'NewProduct features'
            Get-Content -Path (Join-Path $docsDir 'install.md') -Raw | Should -Be 'NEWPRODUCT installation'
            Get-Content -Path (Join-Path $docsDir 'config.md') -Raw | Should -Be 'newproduct configuration'

            $results.Count | Should -Be 3
        }

        It 'Should preserve snake_case in Python code' {
            $pyFile = Join-Path $script:testRoot 'script.py'

            @'
def get_user_name():
    user_name = "admin"
    USER_NAME = "ADMIN"
    return user_name
'@ | Set-Content -Path $pyFile -NoNewline

            $result = Replace-StringInFile -Path $pyFile -OldString 'user_name' -NewString 'account_id' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $pyFile -Raw
            $content | Should -Match 'def get_account_id\(\):'
            $content | Should -Match 'account_id = "admin"'
            $content | Should -Match 'ACCOUNT_ID = "ADMIN"'
            $content | Should -Match 'return account_id'
            $result.MatchCount | Should -Be 4
        }

        It 'Should preserve kebab-case in CSS' {
            $cssFile = Join-Path $script:testRoot 'styles.css'

            @'
:root {
    --primary-color: #007bff;
    --PRIMARY-COLOR: #0056b3;
}
.primary-color {
    color: var(--primary-color);
}
'@ | Set-Content -Path $cssFile -NoNewline

            $result = Replace-StringInFile -Path $cssFile -OldString 'primary-color' -NewString 'brand-color' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $cssFile -Raw
            $content | Should -Match '--brand-color: #007bff;'
            $content | Should -Match '--BRAND-COLOR: #0056b3;'
            $content | Should -Match '\.brand-color \{'
            $content | Should -Match 'var\(--brand-color\);'
            $result.MatchCount | Should -Be 4
        }

        It 'Should preserve SCREAMING_SNAKE_CASE in environment files' {
            $envFile = Join-Path $script:testRoot 'test.env'

            @'
DATABASE_URL=postgresql://localhost/db
database_url=postgresql://localhost/db
DATABASE-URL=postgresql://localhost/db
'@ | Set-Content -Path $envFile -NoNewline

            $result = Replace-StringInFile -Path $envFile -OldString 'database_url' -NewString 'db_connection' -CaseInsensitive -PreserveCase

            $content = Get-Content -Path $envFile -Raw
            $content | Should -Match 'DB_CONNECTION=postgresql://localhost/db'
            $content | Should -Match 'db_connection=postgresql://localhost/db'
            # Note: DATABASE-URL doesn't match database_url search pattern (different separators)
            $result.MatchCount | Should -Be 2
        }
    }

    Context 'PreserveCase with Backup and Recovery' {
        It 'Should allow rollback using backup files' {
            $testFile = Join-Path $script:testRoot 'rollback.txt'
            $originalContent = @'
FooBar is here
FOOBAR is there
foobar everywhere
'@
            $originalContent | Set-Content -Path $testFile -NoNewline

            # Make changes with backup
            $result = Replace-StringInFile -Path $testFile -OldString 'foobar' -NewString 'bazqux' -CaseInsensitive -PreserveCase -Backup

            $result.BackupCreated | Should -Be $true

            # Verify changes were made
            $newContent = Get-Content -Path $testFile -Raw
            $newContent | Should -Not -Be $originalContent

            # Rollback using backup
            Copy-Item -Path "$testFile.bak" -Destination $testFile -Force

            # Verify rollback
            $rolledBack = Get-Content -Path $testFile -Raw
            $rolledBack | Should -Be $originalContent
        }
    }

    Context 'PreserveCase with Different Encodings' {
        It 'Should work with UTF8 encoding' {
            $testFile = Join-Path $script:testRoot 'utf8.txt'
            'Hello café' | Set-Content -Path $testFile -Encoding UTF8 -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase -Encoding UTF8

            $content = Get-Content -Path $testFile -Encoding UTF8 -Raw
            $content | Should -Be 'Goodbye café'
        }

        It 'Should work with ASCII encoding' {
            $testFile = Join-Path $script:testRoot 'ascii.txt'
            'HELLO world' | Set-Content -Path $testFile -Encoding ASCII -NoNewline

            $result = Replace-StringInFile -Path $testFile -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase -Encoding ASCII

            $content = Get-Content -Path $testFile -Encoding ASCII -Raw
            $content | Should -Be 'GOODBYE world'
        }
    }

    Context 'PreserveCase with Large Files' {
        It 'Should handle files with many replacements efficiently' {
            $testFile = Join-Path $script:testRoot 'large.txt'

            # Create content with 1000+ occurrences
            $lines = @()
            for ($i = 1; $i -le 250; $i++)
            {
                $lines += "foo is on line $i"
                $lines += "FOO is on line $i"
                $lines += "Foo is on line $i"
                $lines += "fOo is on line $i"
            }
            $lines -join "`n" | Set-Content -Path $testFile -NoNewline

            # Perform replacement
            $result = Replace-StringInFile -Path $testFile -OldString 'foo' -NewString 'bar' -CaseInsensitive -PreserveCase

            # Verify
            $result.MatchCount | Should -Be 1000
            $result.ReplacementsMade | Should -Be $true

            $content = Get-Content -Path $testFile -Raw
            $content | Should -Match 'bar is on line'
            $content | Should -Match 'BAR is on line'
            $content | Should -Match 'Bar is on line'
        }
    }

    Context 'PreserveCase Error Handling' {
        It 'Should skip binary files when using PreserveCase' {
            # Create a mock binary file
            $binaryFile = Join-Path $script:testRoot 'binary.dat'
            $bytes = @(0x00, 0x01, 0x02, 0xFF, 0xFE, 0x48, 0x65, 0x6C, 0x6C, 0x6F)  # Contains nulls + "Hello"
            [System.IO.File]::WriteAllBytes($binaryFile, $bytes)

            # Attempt replacement - should skip the file
            $result = Replace-StringInFile -Path $binaryFile -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase -WarningAction SilentlyContinue

            # File should be skipped (no result returned or result shows no replacements)
            # The function should continue without error
            $result | Should -BeNullOrEmpty -Because 'Binary files should be skipped'
        }

        It 'Should handle non-existent files gracefully' {
            $nonExistentFile = Join-Path $script:testRoot 'does-not-exist.txt'

            # Should produce an error but not crash
            $result = Replace-StringInFile -Path $nonExistentFile -OldString 'foo' -NewString 'bar' -CaseInsensitive -PreserveCase -ErrorAction SilentlyContinue

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'PreserveCase Comparison with Standard Replacement' {
        It 'Should differ from standard case-insensitive replacement' {
            $file1 = Join-Path $script:testRoot 'standard.txt'
            $file2 = Join-Path $script:testRoot 'preserve.txt'

            $content = 'HELLO hello Hello'
            $content | Set-Content -Path $file1 -NoNewline
            $content | Set-Content -Path $file2 -NoNewline

            # Standard replacement
            $result1 = Replace-StringInFile -Path $file1 -OldString 'hello' -NewString 'goodbye' -CaseInsensitive

            # PreserveCase replacement
            $result2 = Replace-StringInFile -Path $file2 -OldString 'hello' -NewString 'goodbye' -CaseInsensitive -PreserveCase

            $content1 = Get-Content -Path $file1 -Raw
            $content2 = Get-Content -Path $file2 -Raw

            # Standard should replace all with exact replacement text
            $content1 | Should -Be 'goodbye goodbye goodbye'

            # PreserveCase should maintain original case patterns
            $content2 | Should -Be 'GOODBYE goodbye Goodbye'

            # Both should report same match count
            $result1.MatchCount | Should -Be $result2.MatchCount
        }
    }
}
