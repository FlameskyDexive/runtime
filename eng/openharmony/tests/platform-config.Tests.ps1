$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')

Describe 'OpenHarmony runtime platform configuration' {
    It 'defines OpenHarmony as a Unix musl-compatible asset target' {
        $content = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\RuntimeIdentifier.props') -Raw
        $osArch = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\OSArch.props') -Raw

        $content | Should Match "PortableOS.*openharmony.*linux-musl"
        $content | Should Match "TargetsOpenHarmony.*TargetOS.*openharmony"
        $content | Should Match "TargetsLinux.*TargetOS.*openharmony"
        $content | Should Match "TargetsUnix.*TargetsOpenHarmony"
        $osArch | Should Match "TargetsMobile.*TargetOS.*openharmony"
    }

    It 'evaluates the OpenHarmony RID contract in MSBuild' {
        $project = Join-Path $PSScriptRoot 'RuntimeIdentifier.proj'
        $output = & dotnet msbuild $project -target:ValidateOpenHarmony -nologo -verbosity:minimal 2>&1

        $LASTEXITCODE | Should Be 0
        ($output -join [Environment]::NewLine) | Should Match 'OpenHarmony RID contract: linux-musl-arm64'
    }

    It 'accepts OpenHarmony in both public build entry points' {
        $powerShellBuild = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\build.ps1') -Raw
        $shellBuild = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\build.sh') -Raw

        $powerShellBuild | Should Match 'ValidateSet\([^\)]*"openharmony"'
        $shellBuild | Should Match 'openharmony\)'
        $shellBuild | Should Match '__PortableTargetOS=linux-musl'
    }

    It 'uses the official OHOS toolchain in Windows and Unix CMake entry points' {
        $windowsGenerator = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\gen-buildsys.cmd') -Raw
        $unixGenerator = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\gen-buildsys.sh') -Raw

        $windowsGenerator | Should Match '__Os%" == "openharmony"'
        $windowsGenerator | Should Match 'OHOS_TOOLCHAIN_FILE'
        $windowsGenerator | Should Match 'OHOS_ARCH'
        $unixGenerator | Should Match 'target_os" == "openharmony"'
        $unixGenerator | Should Match 'OHOS_TOOLCHAIN_FILE'
        $unixGenerator | Should Match 'OHOS_ARCH'
    }

    It 'does not require a Linux rootfs for an OpenHarmony cross build' {
        $commonBuild = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\build-commons.sh') -Raw

        $commonBuild | Should Match 'targetOS" == openharmony'
        $commonBuild | Should Match '__TargetOS" != "openharmony"'
        $commonBuild | Should Match '__CrossBuild" == 1 && "\$__TargetOS" != "openharmony"'
    }

    It 'defines the dedicated CMake and compiler platform flags' {
        $platform = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\configureplatform.cmake') -Raw
        $compiler = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\configurecompiler.cmake') -Raw

        $platform | Should Match 'CLR_CMAKE_TARGET_OS STREQUAL openharmony'
        $platform | Should Match 'CLR_CMAKE_TARGET_OPENHARMONY 1'
        $compiler | Should Match 'TARGET_OPENHARMONY'
    }
}
