<#
.SYNOPSIS
Downloads and prepares the pinned native dependencies for OpenHarmony runtime builds.

.DESCRIPTION
ICU contributes full public headers. OpenSSL is cross-compiled against the API15
SDK so the same output remains usable by API15/API18/API20/API23/API26 builds.
OpenSSL Configure requires an MSYS/Cygwin Perl and GNU Make on Windows.

.PARAMETER PerlRuntimePath
Adds runtime directories required by a portable MSYS/Cygwin Perl, such as the
directory containing msys-2.0.dll. A complete MSYS2 installation does not need it.

.EXAMPLE
.\prepare-dependencies.ps1 -Perl C:\msys64\usr\bin\perl.exe -Make C:\msys64\usr\bin\make.exe
#>
[CmdletBinding()]
param(
    [string] $SdkRoot = (Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk'),

    [int] $ApiLevel = 15,

    [ValidateSet('arm64', 'x64')]
    [string] $Architecture = 'arm64',

    [string] $OutputRoot,

    [string] $CacheRoot,

    [string] $WorkRoot,

    [string] $Perl = 'perl',

    [string[]] $PerlRuntimePath = @(),

    [string] $Make = 'make',

    [string] $IcuBuildRoot,

    [switch] $ForceBuild
)

$ErrorActionPreference = 'Stop'
$isWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if ($ApiLevel -ne 15) {
    throw 'OpenHarmony native dependencies must be built against the API15 compatibility baseline and reused by API18/API20/API23/API26 runtime builds.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$manifestPath = Join-Path $PSScriptRoot 'dependencies.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$sdk = & (Join-Path $PSScriptRoot 'validate-sdk.ps1') `
    -SdkRoot $SdkRoot `
    -ApiLevel $ApiLevel `
    -Architecture $Architecture

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'artifacts\openharmony\dependencies'
}
if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = Join-Path $repoRoot 'artifacts\openharmony\downloads'
}
if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
    $WorkRoot = Join-Path $repoRoot 'artifacts\openharmony\dependency-work'
}

function Get-ResolvedTool {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command,

        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    if (Test-Path -LiteralPath $Command -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Command).Path
    }

    $resolved = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $resolved) {
        throw "$Description was not found. Pass its executable path explicitly."
    }

    return $resolved.Source
}

function Get-VerifiedArchive {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject] $Dependency
    )

    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
    $archivePath = Join-Path $CacheRoot $Dependency.archive
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        Write-Host "Downloading $($Dependency.url)"
        $temporaryPath = Join-Path $CacheRoot ([IO.Path]::GetRandomFileName())
        try {
            Invoke-WebRequest -Uri $Dependency.url -OutFile $temporaryPath
            Move-Item -LiteralPath $temporaryPath -Destination $archivePath
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
    }

    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ($actualHash -ne $Dependency.sha256) {
        throw "SHA256 mismatch for '$archivePath': expected '$($Dependency.sha256)', found '$actualHash'."
    }

    return $archivePath
}

function Expand-VerifiedArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ArchivePath,

        [Parameter(Mandatory = $true)]
        [string] $Destination,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedPath,

        [switch] $Force
    )

    if ($Force -and (Test-Path -LiteralPath $Destination -PathType Container)) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    if (Test-Path -LiteralPath $ExpectedPath) {
        return
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & tar -xf $ArchivePath -C $Destination
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract '$ArchivePath'."
    }
    if (-not (Test-Path -LiteralPath $ExpectedPath)) {
        throw "Archive '$ArchivePath' did not contain the expected path '$ExpectedPath'."
    }
}

function Write-DependencyMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Destination,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [PSObject] $Dependency
    )

    $metadata = [ordered]@{
        name = $Name
        version = [string]$Dependency.version
        source = [string]$Dependency.url
        sha256 = [string]$Dependency.sha256
        license = [string]$Dependency.license
        sdkApiLevel = $sdk.ApiLevel
        sdkPackageVersion = $sdk.PackageVersion
        architecture = $sdk.Architecture
        targetTriple = $sdk.TargetTriple
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Destination 'dependency-metadata.json') -Encoding Ascii
}

function Test-StagedDependencyMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][PSObject]$Definition,
        [Parameter(Mandatory = $true)][string]$Architecture,
        [Parameter(Mandatory = $true)][string]$TargetTriple,
        [string]$MetadataName = 'dependency-metadata.json'
    )

    $metadataPath = Join-Path $Root $MetadataName
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        return $false
    }

    try {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        return $metadata.name -eq $Name -and
            $metadata.version -eq [string]$Definition.version -and
            $metadata.source -eq [string]$Definition.url -and
            $metadata.sha256 -eq [string]$Definition.sha256 -and
            $metadata.license -eq [string]$Definition.license -and
            [int]$metadata.sdkApiLevel -eq 15 -and
            $metadata.sdkPackageVersion -eq $sdk.PackageVersion -and
            $metadata.architecture -eq $Architecture -and
            $metadata.targetTriple -eq $TargetTriple
    }
    catch {
        return $false
    }
}

function Repair-OpenSslArchives {
    param(
        [Parameter(Mandatory = $true)][string]$MakePath,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string[]]$MakeArguments,
        [Parameter(Mandatory = $true)][string]$ArchiveTool,
        [Parameter(Mandatory = $true)][string]$RanlibTool
    )

    $archives = @(
        @{ Target = 'libcrypto.a'; Output = 'libcrypto.a'; Prefix = 'llvm-ar qc libcrypto.a ' },
        @{ Target = 'libssl.a'; Output = 'libssl.a'; Prefix = 'llvm-ar qc libssl.a ' },
        @{ Target = 'providers/libcommon.a'; Output = 'providers/libcommon.a'; Prefix = 'llvm-ar qc providers/libcommon.a ' },
        @{ Target = 'providers/libdefault.a'; Output = 'providers/libdefault.a'; Prefix = 'llvm-ar qc providers/libdefault.a ' },
        @{ Target = 'providers/liblegacy.a'; Output = 'providers/liblegacy.a'; Prefix = 'llvm-ar qc providers/liblegacy.a ' },
        @{ Target = 'providers/libtemplate.a'; Output = 'providers/libtemplate.a'; Prefix = 'llvm-ar qc providers/libtemplate.a ' }
    )

    Push-Location $SourceRoot
    try {
        foreach ($archive in $archives) {
            $archivePath = Join-Path $SourceRoot $archive.Output
            if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
                Remove-Item -LiteralPath $archivePath -Force
            }

            $dryRunArguments = @($MakeArguments) + @('-n', $archive.Target)
            $dryRun = @(& $MakePath @dryRunArguments 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "GNU Make could not produce the dry-run command for '$($archive.Target)'."
            }
            $objectPaths = [System.Collections.Generic.List[string]]::new()
            $dryRunText = $dryRun -join [Environment]::NewLine
            $outputPattern = [regex]::Escape(($archive.Output -replace '\\', '/'))
            $commandPattern = "(?im)(?:^|[\r\n])\s*(?:[^\s]+[/\\])?llvm-ar(?:\.exe)?\s+qc\s+$outputPattern\s+([^\r\n]+)"
            $commandMatch = [regex]::Match($dryRunText, $commandPattern)
            if ($commandMatch.Success) {
                foreach ($argument in ($commandMatch.Groups[1].Value.Trim() -split '\s+')) {
                    if (-not [string]::IsNullOrWhiteSpace($argument)) {
                        $objectPaths.Add($argument)
                    }
                }
            }

            if ($objectPaths.Count -eq 0) {
                throw "OpenSSL archive '$($archive.Target)' did not produce an object list for response-file repair."
            }

            $responseFile = "$archivePath.rsp"
            Set-Content -LiteralPath $responseFile -Value $objectPaths -Encoding ascii
            & $ArchiveTool qc $archivePath "@$responseFile"
            if ($LASTEXITCODE -ne 0) {
                throw "llvm-ar failed while repairing OpenSSL archive '$($archive.Target)'."
            }

            & $RanlibTool $archivePath
            if ($LASTEXITCODE -ne 0) {
                throw "llvm-ranlib failed while repairing OpenSSL archive '$($archive.Target)'."
            }
            Remove-Item -LiteralPath $responseFile -Force
        }
    }
    finally {
        Pop-Location
    }
}

$icuArchive = Get-VerifiedArchive -Dependency $manifest.icu
$icuWorkRoot = Join-Path $WorkRoot "icu-$($manifest.icu.version)"
$icuSourceRoot = Join-Path $icuWorkRoot 'icu'
$icuHeaders = Join-Path $icuSourceRoot 'source\common\unicode'
Expand-VerifiedArchive -ArchivePath $icuArchive -Destination $icuWorkRoot -ExpectedPath $icuHeaders -Force:$ForceBuild

$icuOutput = Join-Path $OutputRoot "icu\$($sdk.OhosArch)"
$icuOutputHeaders = Join-Path $icuOutput 'include\unicode'
$icuOutputLib = Join-Path $icuOutput 'lib'
$requiredIcuLibraries = @('libicuuc.so.78', 'libicui18n.so.78', 'libicudata.so.78')
$icuOutputComplete = (Test-StagedDependencyMetadata `
        -Root $icuOutput `
        -Name 'icu' `
        -Definition $manifest.icu `
        -Architecture $sdk.Architecture `
        -TargetTriple $sdk.TargetTriple) -and
    (@($requiredIcuLibraries | Where-Object { -not (Test-Path -LiteralPath (Join-Path $icuOutputLib $_) -PathType Leaf) }).Count -eq 0)
if ($icuOutputComplete -and -not $ForceBuild) {
    Write-Host "Reusing staged ICU $($sdk.OhosArch) dependency."
}
else {
    if ([string]::IsNullOrWhiteSpace($IcuBuildRoot)) {
        throw "ICU output for $($sdk.TargetTriple) is not staged. Pass -IcuBuildRoot to an ICU 78.3 build produced for API15/$($sdk.TargetTriple), including openharmony-icu-provenance.json."
    }
    $icuBuildLib = Join-Path $IcuBuildRoot 'lib'
    $icuBuildProvenancePath = Join-Path $IcuBuildRoot 'openharmony-icu-provenance.json'
    if (-not (Test-StagedDependencyMetadata `
            -Root $IcuBuildRoot `
            -Name 'icu' `
            -Definition $manifest.icu `
            -Architecture $sdk.Architecture `
            -TargetTriple $sdk.TargetTriple `
            -MetadataName 'openharmony-icu-provenance.json')) {
        throw "ICU build provenance '$icuBuildProvenancePath' is missing or does not match ICU $($manifest.icu.version), API15, $($sdk.TargetTriple)."
    }
    foreach ($libraryName in $requiredIcuLibraries) {
        if (-not (Test-Path -LiteralPath (Join-Path $icuBuildLib $libraryName) -PathType Leaf)) {
            throw "Built ICU library '$libraryName' was not found under '$icuBuildLib'. Build ICU 78.3 for $($sdk.TargetTriple) and pass the build directory through -IcuBuildRoot."
        }
    }
}
New-Item -ItemType Directory -Path $icuOutputHeaders -Force | Out-Null
foreach ($headerRoot in @('common\unicode', 'i18n\unicode', 'io\unicode')) {
    $headerPath = Join-Path $icuSourceRoot "source\$headerRoot"
    if (Test-Path -LiteralPath $headerPath -PathType Container) {
        Copy-Item -Path (Join-Path $headerPath '*') -Destination $icuOutputHeaders -Recurse -Force
    }
}
New-Item -ItemType Directory -Path $icuOutputLib -Force | Out-Null
if (-not $icuOutputComplete -or $ForceBuild) {
    foreach ($libraryName in $requiredIcuLibraries) {
        Copy-Item -LiteralPath (Join-Path $icuBuildLib $libraryName) -Destination (Join-Path $icuOutputLib $libraryName) -Force
    }
}
Copy-Item -LiteralPath (Join-Path $icuWorkRoot 'icu\LICENSE') -Destination (Join-Path $icuOutput 'LICENSE') -Force
Write-DependencyMetadata -Destination $icuOutput -Name 'icu' -Dependency $manifest.icu

$opensslOutput = Join-Path $OutputRoot "openssl\$($sdk.OhosArch)"
$opensslMetadata = Join-Path $opensslOutput 'dependency-metadata.json'
$requiredOpenSslFiles = @(
    'include\openssl\opensslv.h',
    'lib\libcrypto.a',
    'lib\libcrypto.so',
    'lib\libcrypto.so.3',
    'lib\libssl.a',
    'lib\libssl.so',
    'lib\libssl.so.3'
)
$opensslComplete = $false
$opensslFilesComplete = @($requiredOpenSslFiles | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $opensslOutput $_) -PathType Leaf)
}).Count -eq 0
if ((Test-Path -LiteralPath $opensslMetadata -PathType Leaf) -and $opensslFilesComplete) {
    try {
        $existingOpenSslMetadata = Get-Content -LiteralPath $opensslMetadata -Raw | ConvertFrom-Json
        $opensslComplete =
            $existingOpenSslMetadata.name -eq 'openssl' -and
            $existingOpenSslMetadata.version -eq $manifest.openssl.version -and
            $existingOpenSslMetadata.source -eq $manifest.openssl.url -and
            $existingOpenSslMetadata.sha256 -eq $manifest.openssl.sha256 -and
            $existingOpenSslMetadata.license -eq $manifest.openssl.license -and
            [int]$existingOpenSslMetadata.sdkApiLevel -eq 15 -and
            $existingOpenSslMetadata.sdkPackageVersion -eq $sdk.PackageVersion -and
            $existingOpenSslMetadata.architecture -eq $sdk.Architecture -and
            $existingOpenSslMetadata.targetTriple -eq $sdk.TargetTriple
    }
    catch {
        $opensslComplete = $false
    }
}

if ($ForceBuild -or -not $opensslComplete) {
    $perlPath = Get-ResolvedTool -Command $Perl -Description 'Perl for configuring OpenSSL'
    $makePath = Get-ResolvedTool -Command $Make -Description 'GNU Make for building OpenSSL'
    $opensslArchive = Get-VerifiedArchive -Dependency $manifest.openssl
    $opensslWorkRoot = Join-Path $WorkRoot "openssl-$($manifest.openssl.version)-api$ApiLevel-$Architecture"
    $opensslSourceRoot = Join-Path $opensslWorkRoot "openssl-$($manifest.openssl.version)"
    Expand-VerifiedArchive `
        -ArchivePath $opensslArchive `
        -Destination $opensslWorkRoot `
        -ExpectedPath (Join-Path $opensslSourceRoot 'Configure') `
        -Force:$ForceBuild

    $target = if ($Architecture -eq 'arm64') { 'linux-aarch64' } else { 'linux-x86_64' }
    $llvmBin = Split-Path $sdk.Clang
    $sysroot = $sdk.Sysroot.Replace('\', '/')
    $compilerFlags = "-target $($sdk.TargetTriple) --sysroot=$sysroot -D__MUSL__"
    $linkerFlags = "-target $($sdk.TargetTriple) --sysroot=$sysroot"
    $environmentNames = @('AR', 'CC', 'CFLAGS', 'CXX', 'CXXFLAGS', 'LDFLAGS', 'PATH', 'PERL5LIB', 'RANLIB', 'SHELL')
    $originalEnvironment = @{}
    foreach ($name in $environmentNames) {
        $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }

    try {
        $perlBin = Split-Path $perlPath
        $makeBin = Split-Path $makePath
        $toolPath = (@($llvmBin, $perlBin) + @($PerlRuntimePath) + @($makeBin, $env:PATH)) -join [IO.Path]::PathSeparator
        [Environment]::SetEnvironmentVariable('PATH', $toolPath, 'Process')
        $perlLibraryPath = Join-Path $repoRoot 'artifacts\openharmony\tools\perl-lib'
        $perlLibrarySource = Join-Path $PSScriptRoot 'perl-lib'
        if (-not (Test-Path -LiteralPath $perlLibrarySource -PathType Container)) {
            throw "Tracked OpenSSL Perl compatibility modules were not found under '$perlLibrarySource'."
        }
        New-Item -ItemType Directory -Path $perlLibraryPath -Force | Out-Null
        Copy-Item -Path (Join-Path $perlLibrarySource '*') -Destination $perlLibraryPath -Recurse -Force
        [Environment]::SetEnvironmentVariable('PERL5LIB', $perlLibraryPath, 'Process')
        $env:PERL5LIB = $perlLibraryPath

        $perlWrapperPath = Join-Path $repoRoot 'artifacts\openharmony\tools\perlwrap.cmd'
        $perlWrapperContent = @(
            '@echo off'
            "set PERL5LIB=$perlLibraryPath"
            "`"$perlPath`" %*"
            'exit /b %ERRORLEVEL%'
        )
        Set-Content -LiteralPath $perlWrapperPath -Value $perlWrapperContent -Encoding ascii

        $shellPath = $null
        if ($isWindowsHost) {
            $shellCommand = Get-Command sh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $shellCommand) {
                $shellPath = $shellCommand.Source
            }
            else {
                $shellCandidates = @(
                    (Join-Path $env:ProgramFiles 'Git\usr\bin\sh.exe'),
                    (Join-Path ${env:ProgramFiles(x86)} 'Git\usr\bin\sh.exe')
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                foreach ($candidate in $shellCandidates) {
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        $shellPath = (Resolve-Path -LiteralPath $candidate).Path
                        break
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($shellPath)) {
                throw 'OpenSSL cross configuration on Windows requires an MSYS/Cygwin sh.exe. Install Git for Windows or MSYS2, or pass a shell through PATH.'
            }
        }
        [Environment]::SetEnvironmentVariable('AR', 'llvm-ar', 'Process')
        [Environment]::SetEnvironmentVariable('CC', 'clang', 'Process')
        [Environment]::SetEnvironmentVariable('CFLAGS', $compilerFlags, 'Process')
        [Environment]::SetEnvironmentVariable('CXX', 'clang++', 'Process')
        [Environment]::SetEnvironmentVariable('CXXFLAGS', $compilerFlags, 'Process')
        [Environment]::SetEnvironmentVariable('LDFLAGS', $linkerFlags, 'Process')
        [Environment]::SetEnvironmentVariable('RANLIB', 'llvm-ranlib', 'Process')
        $perlForMake = $perlWrapperPath.Replace('\', '/')
        $shellForMake = $null
        if ($isWindowsHost) {
            $shellForMake = $shellPath.Replace('\', '/')
            [Environment]::SetEnvironmentVariable('SHELL', $shellForMake, 'Process')
        }

        $perlPlatform = & $perlPath -e 'print "$^O\n"' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Perl could not start. Pass required runtime directories through -PerlRuntimePath.`n$($perlPlatform -join [Environment]::NewLine)"
        }
        if (($perlPlatform -join '') -match 'MSWin32') {
            throw 'OpenSSL cross configuration requires an MSYS/Cygwin Perl that produces Unix paths; native Windows Perl is not supported.'
        }
        Push-Location $opensslSourceRoot
        try {
            & $perlPath .\Configure $target shared no-tests no-apps no-docs no-asm no-module --prefix=/usr/local --libdir=lib
            if ($LASTEXITCODE -ne 0) {
                throw "OpenSSL Configure failed with exit code $LASTEXITCODE."
            }

            if ($isWindowsHost) {
                $opensslMakefile = Join-Path $opensslSourceRoot 'Makefile'
                $makefileText = Get-Content -LiteralPath $opensslMakefile -Raw
                $makefileText = $makefileText -replace '(?m)^SHELL\s*=\s*/bin/sh\s*$', "SHELL = $shellForMake"
                if ($makefileText -notmatch '(?m)^SHELL\s*=') {
                    $makefileText = "SHELL = $shellForMake`n$makefileText"
                }
                $makefileText = $makefileText -replace '(?m)^PERL\s*=.*$', "PERL=$perlForMake"
                Set-Content -LiteralPath $opensslMakefile -Value $makefileText -NoNewline
            }

            $makeArguments = @("-j$([Environment]::ProcessorCount)")
            if ($isWindowsHost) {
                $makeArguments += "SHELL=$shellForMake"
                $makeArguments += "MAKE=$($makePath.Replace('\', '/'))"
                $makeArguments += "PERL=$perlForMake"
            }
            $makeArguments += 'build_libs'
            $makeOutput = @(& $makePath @makeArguments 2>&1)
            $makeExitCode = $LASTEXITCODE
            if ($makeExitCode -ne 0) {
                $makeText = $makeOutput -join [Environment]::NewLine
                if (-not $isWindowsHost -or $makeText -notmatch '(?i)(command line.{0,32}(too long|length)|argument list too long|filename or extension is too long|error\s*87\b|0x57\b)') {
                    throw "OpenSSL build_libs failed with exit code $makeExitCode.`n$makeText"
                }

                Write-Host 'OpenSSL archive build exceeded the Windows command-line limit; retrying archives through response files.'
                $archiveMakeArguments = @($makeArguments | Where-Object { $_ -ne 'build_libs' })
                $archiveTool = Get-ResolvedTool -Command (Join-Path $llvmBin 'llvm-ar.exe') -Description 'HarmonyOS SDK llvm-ar'
                $ranlibTool = Get-ResolvedTool -Command (Join-Path $llvmBin 'llvm-ranlib.exe') -Description 'HarmonyOS SDK llvm-ranlib'
                Repair-OpenSslArchives `
                    -MakePath $makePath `
                    -SourceRoot $opensslSourceRoot `
                    -MakeArguments $archiveMakeArguments `
                    -ArchiveTool $archiveTool `
                    -RanlibTool $ranlibTool
                $makeOutput = @(& $makePath @makeArguments 2>&1)
                $makeExitCode = $LASTEXITCODE
                if ($makeExitCode -ne 0) {
                    throw "OpenSSL build_libs failed after response-file archive repair with exit code $makeExitCode.`n$($makeOutput -join [Environment]::NewLine)"
                }
            }
        }
        finally {
            Pop-Location
        }
    }
    finally {
        foreach ($name in $environmentNames) {
            [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
        }
    }

    $opensslIncludeOutput = Join-Path $opensslOutput 'include\openssl'
    $opensslLibOutput = Join-Path $opensslOutput 'lib'
    New-Item -ItemType Directory -Path $opensslIncludeOutput -Force | Out-Null
    New-Item -ItemType Directory -Path $opensslLibOutput -Force | Out-Null
    Copy-Item -Path (Join-Path $opensslSourceRoot 'include\openssl\*') -Destination $opensslIncludeOutput -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $opensslSourceRoot 'libcrypto.a') -Destination (Join-Path $opensslLibOutput 'libcrypto.a') -Force
    Copy-Item -LiteralPath (Join-Path $opensslSourceRoot 'libcrypto.so.3') -Destination (Join-Path $opensslLibOutput 'libcrypto.so.3') -Force
    Copy-Item -LiteralPath (Join-Path $opensslSourceRoot 'libcrypto.so.3') -Destination (Join-Path $opensslLibOutput 'libcrypto.so') -Force
    Copy-Item -LiteralPath (Join-Path $opensslSourceRoot 'libssl.a') -Destination (Join-Path $opensslLibOutput 'libssl.a') -Force
    Copy-Item -LiteralPath (Join-Path $opensslSourceRoot 'libssl.so.3') -Destination (Join-Path $opensslLibOutput 'libssl.so.3') -Force
    Copy-Item -LiteralPath (Join-Path $opensslSourceRoot 'libssl.so.3') -Destination (Join-Path $opensslLibOutput 'libssl.so') -Force
    Copy-Item -LiteralPath (Join-Path $opensslSourceRoot 'LICENSE.txt') -Destination (Join-Path $opensslOutput 'LICENSE.txt') -Force
    Write-DependencyMetadata -Destination $opensslOutput -Name 'openssl' -Dependency $manifest.openssl
}

$icuVersionHeader = Get-Content -LiteralPath (Join-Path $icuOutputHeaders 'uvernum.h') -Raw
if ($icuVersionHeader -notmatch "U_ICU_VERSION\s+`"$([regex]::Escape($manifest.icu.version))`"") {
    throw "Staged ICU headers do not report version '$($manifest.icu.version)'."
}

$opensslVersionHeader = Get-Content -LiteralPath (Join-Path $opensslOutput 'include\openssl\opensslv.h') -Raw
if ($opensslVersionHeader -notmatch "OPENSSL_VERSION_TEXT\s+`"OpenSSL\s+$([regex]::Escape($manifest.openssl.version))\b") {
    throw "Staged OpenSSL headers do not report version '$($manifest.openssl.version)'."
}

$llvmBin = Split-Path $sdk.Clang
$readElfCandidate = Join-Path $llvmBin 'llvm-readelf.exe'
if (-not (Test-Path -LiteralPath $readElfCandidate -PathType Leaf)) {
    $readElfCandidate = Join-Path $llvmBin 'llvm-readelf'
}
$readElf = Get-ResolvedTool -Command $readElfCandidate -Description 'HarmonyOS SDK llvm-readelf'
$expectedMachine = if ($Architecture -eq 'arm64') { 'AArch64' } else { 'Advanced Micro Devices X86-64' }
$expectedDynamic = [ordered]@{
    'libicuuc.so.78' = @('libc++_shared.so', 'libc.so', 'libicudata.so.78')
    'libicui18n.so.78' = @('libc++_shared.so', 'libc.so', 'libicudata.so.78', 'libicuuc.so.78')
    'libicudata.so.78' = @('libc.so')
    'libcrypto.so.3' = @('libc.so')
    'libssl.so.3' = @('libc.so', 'libcrypto.so.3')
}
foreach ($entry in $expectedDynamic.GetEnumerator()) {
    $libraryRoot = if ($entry.Key -like 'libicu*') { $icuOutput } else { $opensslOutput }
    $libraryPath = Join-Path $libraryRoot "lib\$($entry.Key)"
    $header = & $readElf -h $libraryPath 2>&1
    if ($LASTEXITCODE -ne 0 -or ($header -join [Environment]::NewLine) -notmatch "Machine:\s+$([regex]::Escape($expectedMachine))") {
        throw "Staged OpenSSL library '$libraryPath' is not an $expectedMachine ELF file."
    }

    $dynamic = & $readElf -d $libraryPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect dynamic metadata for '$libraryPath'."
    }
    $dynamicText = $dynamic -join [Environment]::NewLine
    if ($dynamicText -notmatch "\(SONAME\)\s+Library soname: \[$([regex]::Escape($entry.Key))\]") {
        throw "Staged OpenSSL library '$libraryPath' has an unexpected SONAME."
    }
    $actualDependencies = @($dynamic | ForEach-Object {
        if ($_ -match '\(NEEDED\)\s+Shared library: \[([^\]]+)\]') {
            $Matches[1]
        }
    } | Sort-Object -Unique)
    $dependencyDifferences = @(Compare-Object -ReferenceObject @($entry.Value | Sort-Object) -DifferenceObject $actualDependencies)
    if ($dependencyDifferences.Count -ne 0) {
        throw "Staged OpenSSL library '$libraryPath' has unexpected dependencies: $($actualDependencies -join ', ')."
    }
}

Write-Host "Prepared OpenHarmony dependencies for API $ApiLevel $Architecture under '$OutputRoot'."
