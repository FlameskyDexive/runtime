$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$sdkRoot = Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk'

Describe 'OpenHarmony runtime artifact verification' {
    It 'pins reproducible OpenSSL and ICU sources' {
        $manifestPath = Join-Path $repoRoot 'eng\openharmony\dependencies.json'
        Test-Path -LiteralPath $manifestPath -PathType Leaf | Should Be $true

        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.openssl.version | Should Be '3.5.7'
        $manifest.openssl.sha256 | Should Be 'A8C0D28A529CA480F9F36CF5792E2CD21984552A3C8E4AA11A24AA31AEAC98E8'
        $manifest.openssl.url | Should Match '^https://github\.com/openssl/openssl/releases/'
        $manifest.icu.version | Should Be '78.3'
        $manifest.icu.sha256 | Should Be '20B295E2C23C541AEC17F35C546E4D3136B7AB7D58E3A5FC4E479958A69B1A2C'
        $manifest.icu.url | Should Match '^https://github\.com/unicode-org/icu/releases/'
    }

    It 'prepares dependencies through the pinned manifest and verifies every download hash' {
        $scriptPath = Join-Path $repoRoot 'eng\openharmony\prepare-dependencies.ps1'
        Test-Path -LiteralPath $scriptPath -PathType Leaf | Should Be $true

        $content = Get-Content -LiteralPath $scriptPath -Raw
        $content | Should Match 'dependencies\.json'
        $content | Should Match 'Get-FileHash'
        $content | Should Match 'build_libs'
        $content | Should Match 'include\\unicode'
        $content | Should Match 'libcrypto\.so\.3'
        $content | Should Match 'llvm-readelf'
        $content | Should Match 'existingOpenSslMetadata'
    }

    It 'keeps external ICU and Windows OpenSSL tooling provenance portable' {
        $scriptPath = Join-Path $repoRoot 'eng\openharmony\prepare-dependencies.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw

        $content | Should Match 'openharmony-icu-provenance\.json'
        $content | Should Match 'MetadataName'
        $content | Should Match 'Get-Command sh\.exe'
        $content | Should Match 'perl-lib'
        $content | Should Match '\[Environment\]::OSVersion\.Platform'
        $content | Should Not Match '\$IsWindows\b'
        $content | Should Not Match 'C:\\Program Files\\Git'
        $content | Should Not Match 'Progra~1'
        foreach ($modulePath in @(
            'eng\openharmony\perl-lib\Locale\Maketext\Simple.pm',
            'eng\openharmony\perl-lib\ExtUtils\MakeMaker.pm',
            'eng\openharmony\perl-lib\Pod\Usage.pm')) {
            Test-Path -LiteralPath (Join-Path $repoRoot $modulePath) -PathType Leaf | Should Be $true
        }
    }

    It 'binds runtime verification to the source commit and dirty state' {
        $scriptPath = Join-Path $repoRoot 'eng\openharmony\verify-runtime.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw

        $content | Should Match "rev-parse', 'HEAD"
        $content | Should Match "status', '--porcelain"
        $content | Should Match 'sourceCommit'
        $content | Should Match 'sourceDirty'
    }

    It 'keeps native dependencies at the API15 compatibility baseline' {
        $scriptPath = Join-Path $repoRoot 'eng\openharmony\prepare-dependencies.ps1'

        { & $scriptPath -SdkRoot $TestDrive -ApiLevel 18 -Architecture arm64 } | Should Throw 'API15 compatibility baseline'
    }

    It 'requires staged dependency provenance before starting a runtime build' {
        $scriptPath = Join-Path $repoRoot 'eng\openharmony\build-runtime.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw

        $content | Should Match 'dependencies\.json'
        $content | Should Match 'dependency-metadata\.json'
        $content | Should Match 'sha256'
        $content | Should Match 'sdkApiLevel'
        $content | Should Match 'sdkPackageVersion'
    }

    $aotSdkPath = Join-Path $repoRoot 'artifacts\bin\coreclr\openharmony.arm64.Release\aotsdk'
    It 'verifies the complete API15 arm64 runtime output' -Skip:(-not (Test-Path -LiteralPath $aotSdkPath -PathType Container)) {
        $scriptPath = Join-Path $repoRoot 'eng\openharmony\verify-runtime.ps1'
        Test-Path -LiteralPath $scriptPath -PathType Leaf | Should Be $true

        $output = & $scriptPath -SdkRoot $sdkRoot -ApiLevel 15 -Architecture arm64 -Configuration Release 2>&1
        $LASTEXITCODE | Should Be 0
        ($output -join [Environment]::NewLine) | Should Match 'Verified OpenHarmony API 15 arm64 Release runtime'
    }

    $nativeOutputPath = Join-Path $repoRoot 'artifacts\bin\microsoft.netcore.app.runtime.linux-musl-arm64\Release\runtimes\linux-musl-arm64\native'
    It 'ships the OpenSSL runtime libraries beside the crypto shim' -Skip:(-not (Test-Path -LiteralPath $aotSdkPath -PathType Container)) {
        Test-Path -LiteralPath (Join-Path $nativeOutputPath 'libcrypto.so.3') -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path $nativeOutputPath 'libssl.so.3') -PathType Leaf | Should Be $true
    }

    It 'ships versioned ICU and C++ runtime libraries beside globalization' -Skip:(-not (Test-Path -LiteralPath $aotSdkPath -PathType Container)) {
        foreach ($fileName in @('libicuuc.so.78', 'libicui18n.so.78', 'libicudata.so.78', 'libc++_shared.so')) {
            Test-Path -LiteralPath (Join-Path $nativeOutputPath $fileName) -PathType Leaf | Should Be $true
        }
    }

    It 'rejects an API15 output when verification requests API26' -Skip:(-not (Test-Path -LiteralPath $aotSdkPath -PathType Container)) {
        {
            & (Join-Path $repoRoot 'eng\openharmony\verify-runtime.ps1') -SdkRoot $sdkRoot -ApiLevel 26 -Architecture arm64 -Configuration Release
        } | Should Throw
    }
}
