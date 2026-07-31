$scriptPath = Join-Path $PSScriptRoot '..\validate-sdk.ps1'

function New-TestSdk {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Folder,

        [Parameter(Mandatory = $true)]
        [int] $ApiLevel
    )

    $nativeRoot = Join-Path $Root "$Folder\native"
    $clangPath = Join-Path $nativeRoot 'llvm\bin\clang.exe'
    $clangxxPath = Join-Path $nativeRoot 'llvm\bin\clang++.exe'
    $lldPath = Join-Path $nativeRoot 'llvm\bin\ld.lld.exe'
    $cmakePath = Join-Path $nativeRoot 'build-tools\cmake\bin\cmake.exe'
    $ninjaPath = Join-Path $nativeRoot 'build-tools\cmake\bin\ninja.exe'
    $toolchainPath = Join-Path $nativeRoot 'build\cmake\ohos.toolchain.cmake'
    $sysrootPath = Join-Path $nativeRoot 'sysroot'

    New-Item -ItemType Directory -Force -Path (Split-Path $clangPath), (Split-Path $cmakePath), (Split-Path $toolchainPath), $sysrootPath | Out-Null
    New-Item -ItemType File -Force -Path $clangPath, $clangxxPath, $lldPath, $cmakePath, $ninjaPath, $toolchainPath | Out-Null
    @{
        apiVersion = "$ApiLevel"
        path = 'native'
        releaseType = 'Release'
        version = 'test'
    } | ConvertTo-Json | Set-Content -Path (Join-Path $nativeRoot 'oh-uni-package.json')
}

Describe 'OpenHarmony SDK validation' {
    BeforeEach {
        $sdkRoot = Join-Path $TestDrive 'Sdk'
        New-TestSdk -Root $sdkRoot -Folder '15' -ApiLevel 15
        New-TestSdk -Root $sdkRoot -Folder '26.0.0' -ApiLevel 26
    }

    It 'maps arm64 to the official OHOS ABI and target triple' {
        $result = & $scriptPath -SdkRoot $sdkRoot -ApiLevel 15 -Architecture arm64

        $result.ApiLevel | Should Be 15
        $result.SdkFolder | Should Be '15'
        $result.OhosArch | Should Be 'arm64-v8a'
        $result.TargetTriple | Should Be 'aarch64-linux-ohos'
        $result.Sysroot | Should Match '15[\\/]native[\\/]sysroot$'
        $result.Clang | Should Match 'clang\.exe$'
        $result.ClangXX | Should Match 'clang\+\+\.exe$'
        $result.Linker | Should Match 'ld\.lld\.exe$'
        $result.CMake | Should Match 'cmake\.exe$'
        $result.Ninja | Should Match 'ninja\.exe$'
    }

    It 'maps x64 to the official OHOS ABI and target triple' {
        $result = & $scriptPath -SdkRoot $sdkRoot -ApiLevel 26 -Architecture x64

        $result.ApiLevel | Should Be 26
        $result.SdkFolder | Should Be '26.0.0'
        $result.OhosArch | Should Be 'x86_64'
        $result.TargetTriple | Should Be 'x86_64-linux-ohos'
    }

    It 'rejects an unsupported API level' {
        { & $scriptPath -SdkRoot $sdkRoot -ApiLevel 14 -Architecture arm64 } |
            Should Throw '15, 18, 20, 23, 26'
    }

    It 'rejects an unsupported architecture' {
        { & $scriptPath -SdkRoot $sdkRoot -ApiLevel 15 -Architecture x86 } |
            Should Throw 'arm64, x64'
    }
}
