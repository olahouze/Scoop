BeforeAll {
    . "$PSScriptRoot\Scoop-TestLib.ps1"
    . "$PSScriptRoot\..\lib\core.ps1"
    . "$PSScriptRoot\..\lib\download.ps1"
}

Describe 'Test-Aria2Enabled' -Tag 'Scoop' {
    It 'should return true if aria2 is installed' {
        Mock Test-HelperInstalled { $true }
        Mock get_config { $true }
        Test-Aria2Enabled | Should-BeTrue
    }

    It 'should return false if aria2 is not installed' {
        Mock Test-HelperInstalled { $false }
        Mock get_config { $false }
        Test-Aria2Enabled | Should-BeFalse

        Mock Test-HelperInstalled { $false }
        Mock get_config { $true }
        Test-Aria2Enabled | Should-BeFalse

        Mock Test-HelperInstalled { $true }
        Mock get_config { $false }
        Test-Aria2Enabled | Should-BeFalse
    }
}

Describe 'New-DownloadRequest Accept header' -Tag 'Scoop' {
    BeforeAll {
        Mock Get-UserAgent { 'Scoop-Test' }
        Mock Get-GitHubToken { 'fake-token' }
        Mock get_config { }
    }

    It 'omits the Accept header for an Actions artifact zip so it is not rejected with 415' {
        $req = New-DownloadRequest 'https://api.github.com/repos/example/example/actions/artifacts/11138249207/zip'
        $req.Accept | Should-BeNull
    }

    It 'omits the Accept header for an artifact zip even when a filename-override fragment is appended' {
        # Exercises the $reqUrl fragment-strip + Accept-check interaction (the original bug)
        $req = New-DownloadRequest 'https://api.github.com/repos/example/example/actions/artifacts/11138249207/zip#/example.zip'
        $req.Accept | Should-BeNull
    }

    It 'sets octet-stream Accept for a release asset so it returns the binary' {
        $req = New-DownloadRequest 'https://api.github.com/repos/example/example/releases/assets/599854636'
        $req.Accept | Should-Be 'application/octet-stream'
    }

    It 'sets octet-stream Accept for other api.github.com paths' {
        $req = New-DownloadRequest 'https://api.github.com/repos/example/example/actions/artifacts/11138249207'
        $req.Accept | Should-Be 'application/octet-stream'
    }
}

Describe 'url_filename' -Tag 'Scoop' {
    It 'should extract the real filename from an url' {
        url_filename 'http://example.org/foo.txt' | Should-Be 'foo.txt'
        url_filename 'http://example.org/foo.txt?var=123' | Should-Be 'foo.txt'
    }

    It 'can be tricked with a hash to override the real filename' {
        url_filename 'http://example.org/foo-v2.zip#/foo.zip' | Should-Be 'foo.zip'
    }
}

Describe 'url_remote_filename' -Tag 'Scoop' {
    It 'should extract the real filename from an url' {
        url_remote_filename 'http://example.org/foo.txt' | Should-Be 'foo.txt'
        url_remote_filename 'http://example.org/foo.txt?var=123' | Should-Be 'foo.txt'
    }

    It 'can not be tricked with a hash to override the real filename' {
        url_remote_filename 'http://example.org/foo-v2.zip#/foo.zip' | Should-Be 'foo-v2.zip'
    }
}

Describe 'Link-OrCopyFile' -Tag 'Scoop' {
    BeforeAll {
        $testDir = Join-Path $env:TEMP ("ScoopLinkTest_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $cacheArchive = Join-Path $testDir 'app.zip'
        Set-Content -Path $cacheArchive -Value 'test archive payload'
        $cacheScript = Join-Path $testDir 'app.ps1'
        Set-Content -Path $cacheScript -Value 'test script payload'
    }
    AfterAll {
        Remove-Item -Recurse -Force $testDir -ErrorAction SilentlyContinue
    }

    It 'hardlinks archive payloads on the same volume' {
        $stagedZip = Join-Path $testDir 'staged.zip'
        Link-OrCopyFile $cacheArchive $stagedZip
        Test-Path $stagedZip | Should-BeTrue
        (Get-Item $stagedZip).LinkType | Should-Be 'HardLink'
    }

    It 'preserves cache file when staged archive link is deleted' {
        $stagedZip = Join-Path $testDir 'staged_delete.zip'
        Link-OrCopyFile $cacheArchive $stagedZip
        Remove-Item $stagedZip -Force
        Test-Path $cacheArchive | Should-BeTrue
        (Get-Content $cacheArchive) | Should-Be 'test archive payload'
    }

    It 'copies non-archive payloads to prevent in-place cache mutation' {
        $stagedScript = Join-Path $testDir 'staged.ps1'
        Link-OrCopyFile $cacheScript $stagedScript
        Test-Path $stagedScript | Should-BeTrue
        Set-Content -Path $stagedScript -Value 'modified script'
        (Get-Content $cacheArchive) | Should-Be 'test archive payload'
        (Get-Content $cacheScript) | Should-Be 'test script payload'
    }

    It 'falls back to copy when hardlink creation fails' {
        $fallbackZip = Join-Path $testDir 'fallback.zip'
        Mock New-Item { throw 'HardLink not supported' } -ParameterFilter { $ItemType -eq 'HardLink' }
        Link-OrCopyFile $cacheArchive $fallbackZip
        Test-Path $fallbackZip | Should-BeTrue
        (Get-Content $fallbackZip) | Should-Be 'test archive payload'
    }
}
