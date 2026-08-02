$buildApiCases = @(
    @{ ApiLevel = 13; Folder = '13' }
    @{ ApiLevel = 14; Folder = '14' }
    @{ ApiLevel = 15; Folder = '15' }
    @{ ApiLevel = 18; Folder = '18' }
    @{ ApiLevel = 20; Folder = '20' }
    @{ ApiLevel = 23; Folder = '23' }
    @{ ApiLevel = 26; Folder = '26.0.0' }
)

$nativeUnavailableCases = @(
    @{ ApiLevel = 16 }
    @{ ApiLevel = 17 }
    @{ ApiLevel = 19 }
    @{ ApiLevel = 21 }
    @{ ApiLevel = 22 }
    @{ ApiLevel = 24 }
)

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\validate-sdk.ps1'
    $buildApiCases = @(
        @{ ApiLevel = 13; Folder = '13' }
        @{ ApiLevel = 14; Folder = '14' }
        @{ ApiLevel = 15; Folder = '15' }
        @{ ApiLevel = 18; Folder = '18' }
        @{ ApiLevel = 20; Folder = '20' }
        @{ ApiLevel = 23; Folder = '23' }
        @{ ApiLevel = 26; Folder = '26.0.0' }
    )

function New-TestSdk {
    param(
        [Parameter(Mandatory = $true)] [string] $Root,
        [Parameter(Mandatory = $true)] [string] $Folder,
        [Parameter(Mandatory = $true)] [int] $ApiLevel,
        [string] $Version = "test-$ApiLevel",
        [string] $ReleaseType = 'Release'
    )

    $nativeRoot = Join-Path $Root "$Folder\native"
    $clangPath = Join-Path $nativeRoot 'llvm\bin\clang.exe'
    $clangxxPath = Join-Path $nativeRoot 'llvm\bin\clang++.exe'
    $lldPath = Join-Path $nativeRoot 'llvm\bin\ld.lld.exe'
    $cmakePath = Join-Path $nativeRoot 'build-tools\cmake\bin\cmake.exe'
    $ninjaPath = Join-Path $nativeRoot 'build-tools\cmake\bin\ninja.exe'
    $toolchainPath = Join-Path $nativeRoot 'build\cmake\ohos.toolchain.cmake'
    $sysrootPath = Join-Path $nativeRoot 'sysroot'
    $manifestPath = Join-Path $nativeRoot 'oh-uni-package.json'

    New-Item -ItemType Directory -Force -Path (Split-Path $clangPath), (Split-Path $cmakePath), (Split-Path $toolchainPath), $sysrootPath | Out-Null
    New-Item -ItemType File -Force -Path $clangPath, $clangxxPath, $lldPath, $cmakePath, $ninjaPath, $toolchainPath | Out-Null
    [ordered]@{
        apiVersion = "$ApiLevel"
        path = 'native'
        releaseType = $ReleaseType
        version = $Version
    } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

    return $manifestPath
}

function Write-TestCatalog {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [object[]] $Packages
    )

    [ordered]@{
        schemaVersion = 1
        supportedApis = @(13..24) + 26
        buildApis = @(13, 14, 15, 18, 20, 23, 26)
        emulatorApis = @(13..24) + 26
        nativeUnavailableApis = @(16, 17, 19, 21, 22, 24)
        nativeUnavailable = @(16, 17, 19, 21, 22, 24) | ForEach-Object {
            [ordered]@{
                apiLevel = $_
                reason = 'No independent Native SDK package is installable for this API; it is not processed as a build target and remains an emulator run target.'
            }
        }
        excludedApis = @(25)
        exclusions = @(
            [ordered]@{
                apiLevel = 25
                reason = 'API 25 is intentionally unsupported because no Native SDK or system image exists.'
            }
        )
        packages = $Packages
        systemImages = @()
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function New-CompleteTestSdkAndCatalog {
    param(
        [Parameter(Mandatory = $true)] [string] $SdkRoot,
        [Parameter(Mandatory = $true)] [string] $CatalogPath
    )

    $packages = foreach ($case in $buildApiCases) {
        $releaseType = if ($case.ApiLevel -eq 26) { 'Beta' } else { 'Release' }
        $manifestPath = New-TestSdk -Root $SdkRoot -Folder $case.Folder -ApiLevel $case.ApiLevel -ReleaseType $releaseType
        [ordered]@{
            apiLevel = $case.ApiLevel
            sdkFolderName = $case.Folder
            version = "test-$($case.ApiLevel)"
            releaseType = $releaseType
            manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
        }
    }

    Write-TestCatalog -Path $CatalogPath -Packages $packages
}
}

Describe 'OpenHarmony SDK validation' {
    BeforeEach {
        $sdkRoot = Join-Path $TestDrive 'Sdk'
        $catalogPath = Join-Path $TestDrive 'sdk-catalog.json'
        New-CompleteTestSdkAndCatalog -SdkRoot $sdkRoot -CatalogPath $catalogPath
    }

    It 'resolves installable Native SDK API <ApiLevel> from catalog folder <Folder>' -ForEach $buildApiCases {
        $result = & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel $ApiLevel -Architecture arm64

        $manifestPath = Join-Path $sdkRoot "$Folder\native\oh-uni-package.json"
        $result.ApiLevel | Should -Be $ApiLevel
        $result.SdkFolder | Should -BeExactly $Folder
        $result.PackageVersion | Should -BeExactly "test-$ApiLevel"
        $result.ManifestSha256 | Should -BeExactly (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    }

    It 'maps arm64 to the official OHOS ABI and target triple' {
        $result = & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel 15 -Architecture arm64

        $result.OhosArch | Should -BeExactly 'arm64-v8a'
        $result.TargetTriple | Should -BeExactly 'aarch64-linux-ohos'
        $result.Sysroot | Should -Match '15[\\/]native[\\/]sysroot$'
        $result.Clang | Should -Match 'clang\.exe$'
        $result.ClangXX | Should -Match 'clang\+\+\.exe$'
        $result.Linker | Should -Match 'ld\.lld\.exe$'
        $result.CMake | Should -Match 'cmake\.exe$'
        $result.Ninja | Should -Match 'ninja\.exe$'
    }

    It 'maps x64 to the official OHOS ABI and target triple' {
        $result = & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel 26 -Architecture x64

        $result.OhosArch | Should -BeExactly 'x86_64'
        $result.TargetTriple | Should -BeExactly 'x86_64-linux-ohos'
    }

    It 'rejects API 25 with the intentional exclusion message' {
        { & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel 25 -Architecture arm64 } |
            Should -Throw '*API 25 is intentionally unsupported*'
    }

    It 'does not process API <ApiLevel> because no installable Native SDK exists' -ForEach $nativeUnavailableCases {
        { & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel $ApiLevel -Architecture arm64 } |
            Should -Throw "*API $ApiLevel does not have an installable Native SDK*not processed*"
    }

    It 'does not probe a system image as the Native SDK for a native-unavailable API' {
        $systemImageRoot = Join-Path $TestDrive 'system-image'
        New-TestSdk -Root $systemImageRoot -Folder '16' -ApiLevel 16 | Out-Null

        { & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -SystemImageRoot $systemImageRoot -ApiLevel 16 -Architecture arm64 } |
            Should -Throw '*API 16 does not have an installable Native SDK*not processed*'
    }

    It 'does not access SystemImageRoot during normal validation' {
        $missingSystemImageRoot = Join-Path $TestDrive 'must-not-be-probed'

        $result = & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -SystemImageRoot $missingSystemImageRoot -ApiLevel 15

        $result.ApiLevel | Should -Be 15
    }

    It 'reports the requested API and expected folder when a package is missing' {
        $emptySdkRoot = Join-Path $TestDrive 'EmptySdk'
        New-Item -ItemType Directory -Path $emptySdkRoot | Out-Null

        { & $scriptPath -SdkRoot $emptySdkRoot -CatalogPath $catalogPath -ApiLevel 26 -Architecture arm64 } |
            Should -Throw '*HarmonyOS API 26 native SDK*26.0.0*'
    }

    It 'rejects an unsupported API outside the target scope' {
        { & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel 12 -Architecture arm64 } |
            Should -Throw '*Supported API levels: 13-24, 26*'
    }

    It 'rejects an unsupported architecture' {
        { & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel 15 -Architecture x86 } |
            Should -Throw '*arm64, x64*'
    }
}

Describe 'OpenHarmony Native SDK manifest validation' {
    BeforeEach {
        $sdkRoot = Join-Path $TestDrive 'Sdk'
        $catalogPath = Join-Path $TestDrive 'sdk-catalog.json'
        New-CompleteTestSdkAndCatalog -SdkRoot $sdkRoot -CatalogPath $catalogPath
        $manifestPath = Join-Path $sdkRoot '15\native\oh-uni-package.json'
        $catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
    }

    It 'rejects a manifest API mismatch' {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $manifest.apiVersion = '14'
        $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

        { & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel 15 } |
            Should -Throw '*native package API mismatch*expected ''15'', found ''14''*'
    }

    It 'rejects a manifest version mismatch' {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $manifest.version = 'unexpected'
        $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

        { & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel 15 } |
            Should -Throw '*native package version mismatch*expected ''test-15'', found ''unexpected''*'
    }

    It 'rejects a manifest release type mismatch' {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $manifest.releaseType = 'Beta'
        $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

        { & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel 15 } |
            Should -Throw '*native package release type mismatch*expected ''Release'', found ''Beta''*'
    }

    It 'rejects a manifest SHA256 mismatch' {
        ($catalog.packages | Where-Object apiLevel -eq 15).manifestSha256 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        $catalog | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $catalogPath -Encoding utf8NoBOM

        { & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel 15 } |
            Should -Throw '*native package SHA256 mismatch*'
    }
}

Describe 'OpenHarmony Native SDK tool validation' {
    BeforeEach {
        $sdkRoot = Join-Path $TestDrive 'Sdk'
        $catalogPath = Join-Path $TestDrive 'sdk-catalog.json'
        New-CompleteTestSdkAndCatalog -SdkRoot $sdkRoot -CatalogPath $catalogPath
    }

    $missingToolCases = @(
        @{ RelativePath = '15\native\sysroot'; Expected = 'sysroot' }
        @{ RelativePath = '15\native\build\cmake\ohos.toolchain.cmake'; Expected = 'CMake toolchain' }
        @{ RelativePath = '15\native\llvm\bin\clang.exe'; Expected = 'Clang was not found' }
        @{ RelativePath = '15\native\llvm\bin\clang++.exe'; Expected = 'Clang++ was not found' }
        @{ RelativePath = '15\native\llvm\bin\ld.lld.exe'; Expected = 'LLD was not found' }
        @{ RelativePath = '15\native\build-tools\cmake\bin\cmake.exe'; Expected = 'CMake was not found' }
        @{ RelativePath = '15\native\build-tools\cmake\bin\ninja.exe'; Expected = 'Ninja was not found' }
    )

    It 'rejects a missing <Expected>' -ForEach $missingToolCases {
        Remove-Item -LiteralPath (Join-Path $sdkRoot $RelativePath) -Force

        { & $scriptPath -SdkRoot $sdkRoot -CatalogPath $catalogPath -ApiLevel 15 } |
            Should -Throw "*$Expected*"
    }
}
