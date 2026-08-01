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

    It 'selects complete Unix library implementations for OpenHarmony' {
        $dotnet = Join-Path $repoRoot '.dotnet\dotnet.exe'
        $projects = @(
            (Join-Path $repoRoot 'src\libraries\sfx-src.proj'),
            (Join-Path $repoRoot 'src\libraries\shims\System\src\System.csproj')
        )

        foreach ($project in $projects) {
            $output = & $dotnet msbuild $project -nologo -getProperty:TargetFramework -p:TargetOS=openharmony -p:TargetArchitecture=arm64 2>&1
            $LASTEXITCODE | Should Be 0
            ($output | Select-Object -Last 1) | Should Be 'net10.0-unix'

            $binPlaceOutput = & $dotnet msbuild $project -nologo -getItem:BinPlaceTargetFrameworks -p:TargetOS=openharmony -p:TargetArchitecture=arm64 2>&1
            $LASTEXITCODE | Should Be 0
            $binPlace = ($binPlaceOutput -join [Environment]::NewLine) | ConvertFrom-Json
            @($binPlace.Items.BinPlaceTargetFrameworks.Identity | Select-Object -Unique) | Should Be @('net10.0-unix')
        }
    }

    It 'uses the official OHOS toolchain in Windows and Unix CMake entry points' {
        $windowsGenerator = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\gen-buildsys.cmd') -Raw
        $unixGenerator = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\gen-buildsys.sh') -Raw

        $windowsGenerator | Should Match '__Os%" == "openharmony"'
        $windowsGenerator | Should Match 'OHOS_TOOLCHAIN_FILE'
        $windowsGenerator | Should Match 'OHOS_ARCH'
        $windowsGenerator | Should Match 'OPENSSL_ROOT_DIR=%OHOS_OPENSSL_ROOT%'
        $windowsGenerator | Should Match 'OPENSSL_INCLUDE_DIR=%OHOS_OPENSSL_ROOT%/include'
        $windowsGenerator | Should Match 'OPENSSL_CRYPTO_LIBRARY=%OHOS_OPENSSL_ROOT%/lib/libcrypto.so'
        $windowsGenerator | Should Match 'OPENSSL_SSL_LIBRARY=%OHOS_OPENSSL_ROOT%/lib/libssl.so'
        $windowsGenerator | Should Match 'ICU_INCLUDE_DIR=%OHOS_ICU_ROOT%/include'
        $unixGenerator | Should Match 'target_os" == "openharmony"'
        $unixGenerator | Should Match 'OHOS_TOOLCHAIN_FILE'
        $unixGenerator | Should Match 'OHOS_ARCH'
        $unixGenerator | Should Match 'OPENSSL_ROOT_DIR=\$OHOS_OPENSSL_ROOT'
        $unixGenerator | Should Match 'OPENSSL_INCLUDE_DIR=\$OHOS_OPENSSL_ROOT/include'
        $unixGenerator | Should Match 'OPENSSL_CRYPTO_LIBRARY=\$OHOS_OPENSSL_ROOT/lib/libcrypto.so'
        $unixGenerator | Should Match 'OPENSSL_SSL_LIBRARY=\$OHOS_OPENSSL_ROOT/lib/libssl.so'
        $unixGenerator | Should Match 'ICU_INCLUDE_DIR=\$OHOS_ICU_ROOT/include'
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
        $compiler | Should Match 'CLR_CMAKE_TARGET_OPENHARMONY[\s\S]*Wno-unused-command-line-argument'
    }

    It 'enables emulated TLS for loadable OpenHarmony NativeAOT modules' {
        $nativeAot = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\nativeaot\CMakeLists.txt') -Raw
        $vm = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\vm\CMakeLists.txt') -Raw

        $nativeAot | Should Match 'CLR_CMAKE_TARGET_ANDROID OR CLR_CMAKE_TARGET_OPENHARMONY'
        $nativeAot | Should Match 'FEATURE_EMULATED_TLS'
        $vm | Should Match 'CLR_CMAKE_TARGET_ANDROID OR CLR_CMAKE_TARGET_OPENHARMONY'
        $vm | Should Match 'FEATURE_EMULATED_TLS'
    }

    It 'maps the OHOS CMake system and SDK architectures to .NET host flags' {
        $platform = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\configureplatform.cmake') -Raw

        $platform | Should Match 'CLR_CMAKE_HOST_OS STREQUAL ohos'
        $platform | Should Match 'CLR_CMAKE_HOST_OPENHARMONY 1'
        $platform | Should Match 'CLR_CMAKE_HOST_LINUX_MUSL 1'
        $platform | Should Match 'CMAKE_SYSTEM_PROCESSOR STREQUAL aarch64[\s\S]*CLR_CMAKE_HOST_UNIX_ARM64 1'
        $platform | Should Match 'CMAKE_SYSTEM_PROCESSOR STREQUAL x86_64[\s\S]*CLR_CMAKE_HOST_UNIX_AMD64 1'
    }

    It 'does not run Linux bash introspection for the OpenHarmony CMake host' {
        $tools = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\configuretools.cmake') -Raw

        $tools | Should Match 'CLR_CMAKE_HOST_LINUX AND NOT CLR_CMAKE_HOST_OPENHARMONY'
    }

    It 'detects the OpenHarmony ELF linker from the SDK linker executable' {
        $tools = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\configuretools.cmake') -Raw
        $functions = Get-Content -LiteralPath (Join-Path $repoRoot 'eng\native\functions.cmake') -Raw

        $tools | Should Match 'CLR_CMAKE_HOST_OPENHARMONY[\s\S]*CMAKE_LINKER\} --version'
        $functions | Should Match 'CLR_CMAKE_TARGET_OPENHARMONY[^\r\n]*LD_LLVM[\s\S]*--version-script'
    }

    It 'generates Unix version sources for Windows-hosted OpenHarmony cross builds' {
        $coreClrBuild = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\build-runtime.cmd') -Raw
        $nativeLibrariesBuild = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\libs\build-native.cmd') -Raw

        $coreClrBuild | Should Match '__TargetOS%"=="openharmony"[\s\S]*set __CrossTarget=1'
        $nativeLibrariesBuild | Should Match '__TargetOS%"=="openharmony"[\s\S]*set __CrossTarget=1'
        $coreClrBuild | Should Match 'copy_version_files\.ps1'
        $nativeLibrariesBuild | Should Match 'copy_version_files\.ps1'
    }

    It 'uses explicit full ICU headers and packaged versioned ICU libraries' {
        $globalization = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\libs\System.Globalization.Native\CMakeLists.txt') -Raw
        $icuShim = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\libs\System.Globalization.Native\pal_icushim.c') -Raw

        $globalization | Should Match 'CLR_CMAKE_TARGET_OPENHARMONY[\s\S]*ICU_INCLUDE_DIR'
        $globalization | Should Match 'ICU_INCLUDE_DIR[\s\S]*unicode/ucurr.h'
        $globalization | Should Match 'unicode/ucurr.h[^\r\n]*NO_CMAKE_FIND_ROOT_PATH'
        $globalization | Should Match 'NOT CLR_CMAKE_TARGET_OPENHARMONY[\s\S]*CMAKE_ICU_DIR'
        $icuShim | Should Match 'FindLibWithMajorVersion'
        $icuShim | Should Not Match 'TARGET_OPENHARMONY[\s\S]*dlopen\("libicu\.so"'
        $icuShim | Should Not Match 'system/usr/ohos_icu'
    }

    It 'disables the unavailable GSS backend without disabling OpenSSL cryptography' {
        $nativeLibraries = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\libs\CMakeLists.txt') -Raw
        $staticAppHost = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\corehost\apphost\static\CMakeLists.txt') -Raw

        $openHarmonyBranch = [regex]::Match(
            $nativeLibraries,
            'elseif \(CLR_CMAKE_TARGET_OPENHARMONY\)(?<body>[\s\S]*?)elseif')
        $openHarmonyBranch.Success | Should Be $true
        $openHarmonyBranch.Groups['body'].Value | Should Match 'add_subdirectory\(System.Security.Cryptography.Native\)'
        $openHarmonyBranch.Groups['body'].Value | Should Not Match 'System.Net.Security.Native'
        $staticAppHost | Should Match 'NOT CLR_CMAKE_TARGET_OPENHARMONY[^\r\n]*# no gssapi'
        $staticAppHost | Should Match 'System.Security.Cryptography.Native.OpenSsl-Static'
    }

    It 'reads ethtool speed without the unavailable userspace helper' {
        $interfaces = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\libs\System.Native\pal_interfaceaddresses.c') -Raw

        $interfaces | Should Match 'TARGET_OPENHARMONY[\s\S]*ecmd\.speed_hi[\s\S]*ecmd\.speed'
    }

    It 'does not execute Unix entry-point verification scripts from Windows cross builds' {
        $systemNative = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\libs\System.Native\CMakeLists.txt') -Raw
        $compression = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\libs\System.IO.Compression.Native\CMakeLists.txt') -Raw
        $cryptography = Get-Content -LiteralPath (Join-Path $repoRoot 'src\native\libs\System.Security.Cryptography.Native\CMakeLists.txt') -Raw

        $windowsCrossBuild = 'CLR_CMAKE_TARGET_OPENHARMONY[^\r\n]*CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows"'
        $systemNative | Should Match "$windowsCrossBuild[\s\S]*verify-entrypoints\.sh"
        $compression | Should Match "$windowsCrossBuild[\s\S]*verify-entrypoints\.sh"
        $cryptography | Should Match "$windowsCrossBuild[\s\S]*verify-entrypoints\.sh"
    }
}
