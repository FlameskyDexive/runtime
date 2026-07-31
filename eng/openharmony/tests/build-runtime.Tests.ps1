$modulePath = Join-Path $PSScriptRoot '..\OpenHarmonyBuild.psm1'
Import-Module $modulePath -Force

Describe 'OpenHarmony runtime build invocation' {
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

        $invocation.Command | Should Be 'C:\runtime\build.cmd'
        ($invocation.Arguments -contains 'clr.nativeaotruntime+clr.nativeaotlibs+libs') | Should Be $true
        ($invocation.Arguments -contains 'clr.aot+libs') | Should Be $false
        ($invocation.Arguments -contains 'arm64') | Should Be $true
        ($invocation.Arguments -contains 'openharmony') | Should Be $true
        ($invocation.Arguments -contains '/p:FeatureXplatEventSource=false') | Should Be $true
        $invocation.Environment.OHOS_API_LEVEL | Should Be '15'
        $invocation.Environment.OHOS_ARCH | Should Be 'arm64-v8a'
        $invocation.Environment.OHOS_TARGET_TRIPLE | Should Be 'aarch64-linux-ohos'
        $invocation.Environment.OHOS_SYSROOT | Should Be $sdk.Sysroot
        $invocation.Environment.OHOS_TOOLCHAIN_FILE | Should Be $sdk.ToolchainFile
        $invocation.Environment.OHOS_OPENSSL_ROOT | Should Be 'C:\openssl\arm64-v8a'
        $invocation.Environment.OHOS_ICU_ROOT | Should Be 'C:\icu'
        $invocation.Environment.TARGET_BUILD_ARCH | Should Be 'arm64'
        ($invocation.RemoveEnvironment -contains 'ROOTFS_DIR') | Should Be $true
        ($invocation.Environment.Keys -contains 'ROOTFS_DIR') | Should Be $false
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

        ($invocation.Arguments -contains 'x64') | Should Be $true
        ($invocation.Arguments -contains 'Checked') | Should Be $true
        ($invocation.Arguments -contains '/p:ConfigureOnly=true') | Should Be $true
        $invocation.Environment.OHOS_ARCH | Should Be 'x86_64'
        $invocation.Environment.OHOS_API_LEVEL | Should Be '26'
        $invocation.Environment.OHOS_TARGET_TRIPLE | Should Be 'x86_64-linux-ohos'
        $invocation.Environment.OHOS_OPENSSL_ROOT | Should Be 'C:\openssl\x86_64'
        $invocation.Environment.OHOS_ICU_ROOT | Should Be 'C:\icu'
        $invocation.Environment.TARGET_BUILD_ARCH | Should Be 'x64'
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
            ($lines -contains "cwd=$tempRoot") | Should Be $true
            ($lines -contains 'api=15') | Should Be $true
            ($lines -contains 'rootfs=') | Should Be $true
            ($lines -contains 'args=clr.aot+libs -arch arm64') | Should Be $true
            [Environment]::GetEnvironmentVariable('OHOS_API_LEVEL', 'Process') | Should Be 'old-api'
            [Environment]::GetEnvironmentVariable('ROOTFS_DIR', 'Process') | Should Be 'C:\linux-rootfs'
            [Environment]::GetEnvironmentVariable('OHOS_TEST_OUTPUT', 'Process') | Should Be $output
        }
        finally {
            [Environment]::SetEnvironmentVariable('OHOS_API_LEVEL', $oldApi, 'Process')
            [Environment]::SetEnvironmentVariable('ROOTFS_DIR', $oldRootfs, 'Process')
            [Environment]::SetEnvironmentVariable('OHOS_TEST_OUTPUT', $oldOutput, 'Process')
        }
    }
}
