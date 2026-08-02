$discoveryRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$x64AotSdkPath = Join-Path $discoveryRepoRoot 'artifacts\bin\coreclr\openharmony.x64.Release\aotsdk'
$x64ProvenancePath = Join-Path $discoveryRepoRoot 'artifacts\bin\coreclr\openharmony.x64.Release\runtime-build-provenance.json'
$currentSourceCommit = (& git -C $discoveryRepoRoot rev-parse HEAD).Trim()
$currentSourceDirty = -not [string]::IsNullOrWhiteSpace(((& git -C $discoveryRepoRoot status --porcelain --untracked-files=normal) -join "`n"))
$hasCurrentApi15X64Fixture = $false
if ((Test-Path -LiteralPath $x64AotSdkPath -PathType Container) -and (Test-Path -LiteralPath $x64ProvenancePath -PathType Leaf)) {
    $x64Provenance = Get-Content -LiteralPath $x64ProvenancePath -Raw | ConvertFrom-Json
    $hasCurrentApi15X64Fixture =
        [int]$x64Provenance.apiLevel -eq 15 -and
        $x64Provenance.architecture -eq 'x64' -and
        $x64Provenance.configuration -eq 'Release' -and
        $x64Provenance.sourceCommit -eq $currentSourceCommit -and
        [bool]$x64Provenance.sourceDirty -eq $currentSourceDirty
}

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $sdkRoot = Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk'
}

Describe 'OpenHarmony x86_64 NativeAOT runtime' {
    It 'selects the simulator ABI and OHOS target triple' {
        $modulePath = Join-Path $repoRoot 'eng\openharmony\OpenHarmonyBuild.psm1'
        Import-Module $modulePath -Force
        $sdk = [PSCustomObject]@{
            ApiLevel = 15
            Architecture = 'x64'
            OhosArch = 'x86_64'
            TargetTriple = 'x86_64-linux-ohos'
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
            -OpenSslRoot 'C:\deps\openssl\x86_64' `
            -IcuRoot 'C:\deps\icu\x86_64' `
            -Configuration Release

        $invocation.Environment.OHOS_API_LEVEL | Should -Be '15'
        $invocation.Environment.OHOS_ARCH | Should -Be 'x86_64'
        $invocation.Environment.OHOS_TARGET_TRIPLE | Should -Be 'x86_64-linux-ohos'
        $invocation.Environment.TARGET_BUILD_ARCH | Should -Be 'x64'
        ($invocation.Arguments -contains 'x64') | Should -Be $true
        ($invocation.Arguments -contains 'openharmony') | Should -Be $true
    }

    It 'verifies the API15 x86_64 runtime output' -Skip:(-not $hasCurrentApi15X64Fixture) {
        $scriptPath = Join-Path $repoRoot 'eng\openharmony\verify-runtime.ps1'
        $output = & $scriptPath -SdkRoot $sdkRoot -ApiLevel 15 -Architecture x64 -Configuration Release 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'Verified OpenHarmony API 15 x64 Release runtime'
    }
}
