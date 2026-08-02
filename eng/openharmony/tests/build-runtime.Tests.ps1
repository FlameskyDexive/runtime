BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $modulePath = Join-Path $PSScriptRoot '..\OpenHarmonyBuild.psm1'
    $matrixScriptPath = Join-Path $PSScriptRoot '..\run-runtime-matrix.ps1'
    Import-Module $modulePath -Force
}

Describe 'OpenHarmony configured linker dependencies' {
    It 'authorizes deviceinfo from the effective <SdkStyle> shared linker flags' -ForEach @(
        @{ SdkStyle = 'API23 direct'; Flags = '--rtlib=compiler-rt -lunwind -ldeviceinfo_ndk.z' }
        @{ SdkStyle = 'API26 variable'; Flags = '--rtlib=compiler-rt -fuse-ld=lld -ldeviceinfo_ndk.z' }
    ) {
        $cachePath = Join-Path $TestDrive "$($SdkStyle.Replace(' ', '-')).txt"
        "CMAKE_SHARED_LINKER_FLAGS:STRING=$Flags" | Set-Content -LiteralPath $cachePath -Encoding Ascii

        @(Get-OpenHarmonyInjectedSharedDependencies -CMakeCachePath $cachePath) |
            Should -Be @('libdeviceinfo_ndk.z.so')
    }

    It 'ignores commented and inactive toolchain declarations absent from effective flags' {
        $cachePath = Join-Path $TestDrive 'inactive-deviceinfo.txt'
        @(
            '# toolchain source mentioned -ldeviceinfo_ndk.z',
            'CMAKE_SHARED_LINKER_FLAGS:STRING=--rtlib=compiler-rt -fuse-ld=lld'
        ) | Set-Content -LiteralPath $cachePath -Encoding Ascii

        @(Get-OpenHarmonyInjectedSharedDependencies -CMakeCachePath $cachePath) |
            Should -BeNullOrEmpty
    }

    It 'does not accept a dependency flag that only starts with the known name' {
        $cachePath = Join-Path $TestDrive 'lookalike-deviceinfo.txt'
        'CMAKE_SHARED_LINKER_FLAGS:STRING=-ldeviceinfo_ndk.z.untrusted' |
            Set-Content -LiteralPath $cachePath -Encoding Ascii

        @(Get-OpenHarmonyInjectedSharedDependencies -CMakeCachePath $cachePath) |
            Should -BeNullOrEmpty
    }
}

Describe 'OpenHarmony runtime build invocation' {
    It 'isolates API14 x64 artifacts and provenance under the requested root' {
        $artifactsRoot = 'C:\runtime\artifacts\openharmony\api14\x64\Release'
        $sdk = [PSCustomObject]@{
            ApiLevel = 14
            Architecture = 'x64'
            OhosArch = 'x86_64'
            TargetTriple = 'x86_64-linux-ohos'
            NativeRoot = 'C:\sdk\14\native'
            Sysroot = 'C:\sdk\14\native\sysroot'
            ToolchainFile = 'C:\sdk\14\native\build\cmake\ohos.toolchain.cmake'
            Clang = 'C:\sdk\14\native\llvm\bin\clang.exe'
            ClangXX = 'C:\sdk\14\native\llvm\bin\clang++.exe'
            Linker = 'C:\sdk\14\native\llvm\bin\ld.lld.exe'
            CMake = 'C:\sdk\14\native\build-tools\cmake\bin\cmake.exe'
            Ninja = 'C:\sdk\14\native\build-tools\cmake\bin\ninja.exe'
        }

        $invocation = New-OpenHarmonyBuildInvocation `
            -RepoRoot 'C:\runtime' `
            -Sdk $sdk `
            -OpenSslRoot 'C:\openssl\x86_64' `
            -IcuRoot 'C:\icu\x86_64' `
            -Configuration Release `
            -ArtifactsRoot $artifactsRoot

        $invocation.ArtifactsRoot | Should -Be $artifactsRoot
        $invocation.ProvenancePath | Should -Be (Join-Path $artifactsRoot 'runtime-build-provenance.json')
        $invocation.CoreClrOutput | Should -Match 'api14\\x64\\Release\\bin\\coreclr\\openharmony\.x64\.Release$'
        $invocation.Arguments | Should -Contain "/p:ArtifactsDir=$artifactsRoot"
        $invocation.Environment.__RootBinDir | Should -Be $artifactsRoot
    }

    It 'rejects an explicit artifacts root that is not API-qualified' {
        {
            Get-OpenHarmonyArtifactLayout `
                -RepoRoot 'C:\runtime' `
                -ApiLevel 13 `
                -Architecture x64 `
                -Configuration Release `
                -ArtifactsRoot 'C:\shared-runtime-output'
        } | Should -Throw '*must end with*api13\x64\Release*'
    }

    It 'keeps native CoreCLR outputs under a caller-provided root on Windows and Unix' {
        $windowsBuild = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\build-runtime.cmd') -Raw
        $unixBuild = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\build-runtime.sh') -Raw

        $windowsBuild | Should -Match 'if not defined __RootBinDir set "__RootBinDir=%__RepoRootDir%\\artifacts"'
        $windowsBuild | Should -Match 'CLR_ARTIFACTS_OBJ_DIR=!__CMakeArtifactsObjDir!'
        $windowsBuild | Should -Match 'set "__ArtifactsObjDir=%__RootBinDir%\\obj"'
        $windowsBuild | Should -Match 'set "__ArtifactsIntermediatesDir=%__ArtifactsObjDir%\\coreclr\\"'
        $unixBuild | Should -Match 'if \[\[ -z "\$\{__RootBinDir:-\}" \]\]'
        $unixBuild | Should -Match 'CLR_ARTIFACTS_OBJ_DIR=\$__ArtifactsObjDir'

        $configurePaths = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\configurepaths.cmake') -Raw
        $configurePaths | Should -Match 'NOT DEFINED CLR_ARTIFACTS_OBJ_DIR'

        $nativeLibWindowsBuild = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\libs\build-native.cmd') -Raw
        $nativeLibUnixBuild = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\libs\build-native.sh') -Raw
        $nativeLibWindowsBuild | Should -Match 'if defined __RootBinDir'
        $nativeLibWindowsBuild | Should -Match 'CLR_ARTIFACTS_OBJ_DIR=%__cmakeArtifactsObjDir%'
        $nativeLibUnixBuild | Should -Match 'if \[\[ -z "\$\{__RootBinDir:-\}" \]\]'
        $nativeLibUnixBuild | Should -Match 'CLR_ARTIFACTS_OBJ_DIR=\$__ArtifactsObjDir'
    }

    It 'uses API15 and the official arm64 toolchain without a Linux rootfs' {
        $repoRoot = 'C:\runtime'
        $sdk = [PSCustomObject]@{
            ApiLevel = 15
            Architecture = 'arm64'
            OhosArch = 'arm64-v8a'
            TargetTriple = 'aarch64-linux-ohos'
            NativeRoot = 'C:\sdk\15\native'
            Sysroot = 'C:\sdk\15\native\sysroot'
            ToolchainFile = 'C:\sdk\15\native\build\cmake\ohos.toolchain.cmake'
            Clang = 'C:\sdk\15\native\llvm\bin\clang.exe'
            ClangXX = 'C:\sdk\15\native\llvm\bin\clang++.exe'
            Linker = 'C:\sdk\15\native\llvm\bin\ld.lld.exe'
            CMake = 'C:\sdk\15\native\build-tools\cmake\bin\cmake.exe'
            Ninja = 'C:\sdk\15\native\build-tools\cmake\bin\ninja.exe'
        }

        $invocation = New-OpenHarmonyBuildInvocation `
            -RepoRoot $repoRoot `
            -Sdk $sdk `
            -OpenSslRoot 'C:\openssl\arm64-v8a' `
            -IcuRoot 'C:\icu' `
            -Configuration Release

        $invocation.Command | Should -Be 'C:\runtime\build.cmd'
        ($invocation.Arguments -contains 'clr.nativeaotruntime+clr.nativeaotlibs+libs') | Should -Be $true
        ($invocation.Arguments -contains 'clr.aot+libs') | Should -Be $false
        ($invocation.Arguments -contains 'arm64') | Should -Be $true
        ($invocation.Arguments -contains 'openharmony') | Should -Be $true
        ($invocation.Arguments -contains '/p:FeatureXplatEventSource=false') | Should -Be $true
        $invocation.Environment.OHOS_API_LEVEL | Should -Be '15'
        $invocation.Environment.OHOS_ARCH | Should -Be 'arm64-v8a'
        $invocation.Environment.OHOS_TARGET_TRIPLE | Should -Be 'aarch64-linux-ohos'
        $invocation.Environment.OHOS_SYSROOT | Should -Be $sdk.Sysroot
        $invocation.Environment.OHOS_TOOLCHAIN_FILE | Should -Be $sdk.ToolchainFile
        $invocation.Environment.OHOS_OPENSSL_ROOT | Should -Be 'C:\openssl\arm64-v8a'
        $invocation.Environment.OHOS_ICU_ROOT | Should -Be 'C:\icu'
        $invocation.Environment.TARGET_BUILD_ARCH | Should -Be 'arm64'
        ($invocation.RemoveEnvironment -contains 'ROOTFS_DIR') | Should -Be $true
        ($invocation.Environment.Keys -contains 'ROOTFS_DIR') | Should -Be $false
    }

    It 'maps x64 and adds configure-only without changing the SDK contract' {
        $sdk = [PSCustomObject]@{
            ApiLevel = 26
            Architecture = 'x64'
            OhosArch = 'x86_64'
            TargetTriple = 'x86_64-linux-ohos'
            NativeRoot = 'C:\sdk\26.0.0\native'
            Sysroot = 'C:\sdk\26.0.0\native\sysroot'
            ToolchainFile = 'C:\sdk\26.0.0\native\build\cmake\ohos.toolchain.cmake'
            Clang = 'C:\sdk\26.0.0\native\llvm\bin\clang.exe'
            ClangXX = 'C:\sdk\26.0.0\native\llvm\bin\clang++.exe'
            Linker = 'C:\sdk\26.0.0\native\llvm\bin\ld.lld.exe'
            CMake = 'C:\sdk\26.0.0\native\build-tools\cmake\bin\cmake.exe'
            Ninja = 'C:\sdk\26.0.0\native\build-tools\cmake\bin\ninja.exe'
        }

        $invocation = New-OpenHarmonyBuildInvocation `
            -RepoRoot 'D:\runtime' `
            -Sdk $sdk `
            -OpenSslRoot 'C:\openssl\x86_64' `
            -IcuRoot 'C:\icu' `
            -Configuration Checked `
            -ConfigureOnly

        ($invocation.Arguments -contains 'x64') | Should -Be $true
        ($invocation.Arguments -contains 'Checked') | Should -Be $true
        ($invocation.Arguments -contains '/p:ConfigureOnly=true') | Should -Be $true
        $invocation.Arguments[0] | Should -Be 'clr.nativeaotruntime'
        $invocation.Environment.OHOS_ARCH | Should -Be 'x86_64'
        $invocation.Environment.OHOS_API_LEVEL | Should -Be '26'
        $invocation.Environment.OHOS_TARGET_TRIPLE | Should -Be 'x86_64-linux-ohos'
        $invocation.Environment.OHOS_OPENSSL_ROOT | Should -Be 'C:\openssl\x86_64'
        $invocation.Environment.OHOS_ICU_ROOT | Should -Be 'C:\icu'
        $invocation.Environment.TARGET_BUILD_ARCH | Should -Be 'x64'
    }

    It 'passes arguments and restores process environment after the build command exits' {
        $tempRoot = Join-Path $TestDrive 'runtime'
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $command = Join-Path $tempRoot 'fake-build.cmd'
        $output = Join-Path $tempRoot 'build-output.txt'
        @'
@echo off
echo cwd=%CD%> "%OHOS_TEST_OUTPUT%"
echo api=%OHOS_API_LEVEL%>> "%OHOS_TEST_OUTPUT%"
echo rootfs=%ROOTFS_DIR%>> "%OHOS_TEST_OUTPUT%"
echo args=%*>> "%OHOS_TEST_OUTPUT%"
exit /b 0
'@ | Set-Content -Path $command -Encoding Ascii

        $oldApi = [Environment]::GetEnvironmentVariable('OHOS_API_LEVEL', 'Process')
        $oldRootfs = [Environment]::GetEnvironmentVariable('ROOTFS_DIR', 'Process')
        $oldOutput = [Environment]::GetEnvironmentVariable('OHOS_TEST_OUTPUT', 'Process')

        try {
            [Environment]::SetEnvironmentVariable('OHOS_API_LEVEL', 'old-api', 'Process')
            [Environment]::SetEnvironmentVariable('ROOTFS_DIR', 'C:\linux-rootfs', 'Process')
            [Environment]::SetEnvironmentVariable('OHOS_TEST_OUTPUT', $output, 'Process')

            $invocation = [PSCustomObject]@{
                Command = $command
                WorkingDirectory = $tempRoot
                Arguments = @('clr.aot+libs', '-arch', 'arm64')
                Environment = [ordered]@{
                    OHOS_API_LEVEL = '15'
                    OHOS_TEST_OUTPUT = $output
                }
                RemoveEnvironment = @('ROOTFS_DIR')
            }

            Invoke-OpenHarmonyBuild -Invocation $invocation

            $lines = Get-Content $output
            ($lines -contains "cwd=$tempRoot") | Should -Be $true
            ($lines -contains 'api=15') | Should -Be $true
            ($lines -contains 'rootfs=') | Should -Be $true
            ($lines -contains 'args=clr.aot+libs -arch arm64') | Should -Be $true
            [Environment]::GetEnvironmentVariable('OHOS_API_LEVEL', 'Process') | Should -Be 'old-api'
            [Environment]::GetEnvironmentVariable('ROOTFS_DIR', 'Process') | Should -Be 'C:\linux-rootfs'
            [Environment]::GetEnvironmentVariable('OHOS_TEST_OUTPUT', 'Process') | Should -Be $output
        }
        finally {
            [Environment]::SetEnvironmentVariable('OHOS_API_LEVEL', $oldApi, 'Process')
            [Environment]::SetEnvironmentVariable('ROOTFS_DIR', $oldRootfs, 'Process')
            [Environment]::SetEnvironmentVariable('OHOS_TEST_OUTPUT', $oldOutput, 'Process')
        }
    }
}

Describe 'OpenHarmony runtime matrix' {
    It 'rejects API25 before creating an artifacts root' {
        $artifactsBaseRoot = Join-Path $TestDrive 'api25-output'

        {
            & $matrixScriptPath `
                -SdkRoot $TestDrive `
                -Apis 25 `
                -Architectures x64 `
                -Configuration Release `
                -ConfigureOnly `
                -ArtifactsBaseRoot $artifactsBaseRoot
        } | Should -Throw '*API 25*intentionally unsupported*'

        Test-Path -LiteralPath $artifactsBaseRoot | Should -Be $false
    }

    It 'records API16 as an emulator-only skipped build without resolving an SDK' {
        $artifactsBaseRoot = Join-Path $TestDrive 'api16-output'

        $result = & $matrixScriptPath `
            -SdkRoot (Join-Path $TestDrive 'missing-sdk-root') `
            -Apis 16 `
            -Architectures x64 `
            -Configuration Release `
            -ConfigureOnly `
            -ArtifactsBaseRoot $artifactsBaseRoot

        $result.status | Should -Be 'SKIPPED'
        $result.buildApi | Should -Be 16
        $result.buildExitCode | Should -BeNullOrEmpty
        $result.reason | Should -Match '(?i)no.*Native SDK.*installable'
        $summaryPath = Join-Path $artifactsBaseRoot 'api16\x64\Release\runtime-matrix-summary.json'
        Test-Path -LiteralPath $summaryPath -PathType Leaf | Should -Be $true
    }

    It 'writes the failed case summary and stops before the next build API' {
        $artifactsBaseRoot = Join-Path $TestDrive 'failed-output'
        $fakeBuildScript = Join-Path $TestDrive 'fake-build-runtime.ps1'
        $callLog = Join-Path $TestDrive 'matrix-calls.txt'
        @'
[CmdletBinding()]
param(
    [string] $SdkRoot,
    [int] $ApiLevel,
    [string] $Architecture,
    [string] $Configuration,
    [string] $ArtifactsRoot,
    [string] $OpenSslRoot,
    [string] $IcuRoot,
    [switch] $ConfigureOnly
)
Add-Content -LiteralPath $env:OHOS_MATRIX_TEST_CALL_LOG -Value $ApiLevel -Encoding Ascii
throw "synthetic build failure for API $ApiLevel"
'@ | Set-Content -LiteralPath $fakeBuildScript -Encoding Ascii

        $oldCallLog = [Environment]::GetEnvironmentVariable('OHOS_MATRIX_TEST_CALL_LOG', 'Process')
        try {
            [Environment]::SetEnvironmentVariable('OHOS_MATRIX_TEST_CALL_LOG', $callLog, 'Process')
            {
                & $matrixScriptPath `
                    -SdkRoot $TestDrive `
                    -Apis 13, 14 `
                    -Architectures x64 `
                    -Configuration Release `
                    -ConfigureOnly `
                    -ArtifactsBaseRoot $artifactsBaseRoot `
                    -BuildScriptPath $fakeBuildScript
            } | Should -Throw '*synthetic build failure for API 13*'
        }
        finally {
            [Environment]::SetEnvironmentVariable('OHOS_MATRIX_TEST_CALL_LOG', $oldCallLog, 'Process')
        }

        @(Get-Content -LiteralPath $callLog) | Should -Be @('13')
        $failedSummary = Get-Content -LiteralPath (Join-Path $artifactsBaseRoot 'api13\x64\Release\runtime-matrix-summary.json') -Raw | ConvertFrom-Json
        $failedSummary.status | Should -Be 'FAIL'
        $failedSummary.buildExitCode | Should -Be 1
        Test-Path -LiteralPath (Join-Path $artifactsBaseRoot 'api14') | Should -Be $false
    }

    It 'rejects dirty provenance before marking a full build as PASS' {
        $artifactsBaseRoot = Join-Path $TestDrive 'dirty-output'
        $fakeBuildScript = Join-Path $TestDrive 'fake-dirty-build-runtime.ps1'
        $fakeVerifyScript = Join-Path $TestDrive 'fake-verify-runtime.ps1'
        @'
[CmdletBinding()]
param(
    [string] $SdkRoot,
    [int] $ApiLevel,
    [string] $Architecture,
    [string] $Configuration,
    [string] $ArtifactsRoot,
    [string] $OpenSslRoot,
    [string] $IcuRoot,
    [switch] $ConfigureOnly
)
New-Item -ItemType Directory -Path $ArtifactsRoot -Force | Out-Null
@{ sourceDirty = $true; sourceCommit = 'dirty-test' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ArtifactsRoot 'runtime-build-provenance.json') -Encoding Ascii
'@ | Set-Content -LiteralPath $fakeBuildScript -Encoding Ascii
@'
[CmdletBinding()]
param([string] $ArtifactsRoot)
'@ | Set-Content -LiteralPath $fakeVerifyScript -Encoding Ascii

        {
            & $matrixScriptPath `
                -SdkRoot $TestDrive `
                -Apis 13 `
                -Architectures x64 `
                -Configuration Release `
                -ArtifactsBaseRoot $artifactsBaseRoot `
                -BuildScriptPath $fakeBuildScript `
                -VerifyScriptPath $fakeVerifyScript
        } | Should -Throw '*sourceDirty=true*'

        $summary = Get-Content -LiteralPath (Join-Path $artifactsBaseRoot 'api13\x64\Release\runtime-matrix-summary.json') -Raw | ConvertFrom-Json
        $summary.status | Should -Be 'FAIL'
        $summary.reason | Should -Match 'sourceDirty=true'
    }
}
