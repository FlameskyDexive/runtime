[CmdletBinding()]
param(
    [string] $SdkRoot = (Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk'),

    [int] $ApiLevel = 15,

    [ValidateSet('arm64', 'x64')]
    [string] $Architecture = 'arm64',

    [ValidateSet('Debug', 'Checked', 'Release')]
    [string] $Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sdk = & (Join-Path $PSScriptRoot 'validate-sdk.ps1') `
    -SdkRoot $SdkRoot `
    -ApiLevel $ApiLevel `
    -Architecture $Architecture

function Get-GitValue {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $value = & git -C $repoRoot @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read runtime source provenance with git $($Arguments -join ' ')."
    }
    return ($value -join '').Trim()
}

function Assert-RequiredFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required OpenHarmony runtime artifact was not found: $Path"
    }
    if ((Get-Item -LiteralPath $Path).Length -eq 0) {
        throw "OpenHarmony runtime artifact was empty: $Path"
    }
}

function Invoke-CheckedTool {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Tool,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $output = & $Tool @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "'$Tool' with arguments '$($Arguments -join ' ')' failed with exit code $LASTEXITCODE.`n$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

$ridArchitecture = if ($Architecture -eq 'arm64') { 'arm64' } else { 'x64' }
$machine = if ($Architecture -eq 'arm64') { 'AArch64' } else { 'Advanced Micro Devices X86-64' }
$coreClrOutput = Join-Path $repoRoot "artifacts\bin\coreclr\openharmony.$Architecture.$Configuration"
$aotSdk = Join-Path $coreClrOutput 'aotsdk'
$runtimePack = Join-Path $repoRoot "artifacts\bin\microsoft.netcore.app.runtime.linux-musl-$ridArchitecture\$Configuration\runtimes\linux-musl-$ridArchitecture"
$runtimePackRoot = Join-Path $repoRoot "artifacts\bin\microsoft.netcore.app.runtime.linux-musl-$ridArchitecture\$Configuration"
$managedOutput = Join-Path $runtimePack 'lib\net10.0'
$nativeOutput = Join-Path $runtimePack 'native'

$sourceCommit = Get-GitValue -Arguments @('rev-parse', 'HEAD')
$sourceDirty = -not [string]::IsNullOrWhiteSpace((Get-GitValue -Arguments @('status', '--porcelain', '--untracked-files=normal')))

$provenancePath = Join-Path $coreClrOutput 'runtime-build-provenance.json'
Assert-RequiredFile -Path $provenancePath
$provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
$expectedProvenance = [ordered]@{
    apiLevel = $ApiLevel
    sdkFolder = $sdk.SdkFolder
    sdkPackageVersion = $sdk.PackageVersion
    sdkReleaseType = $sdk.ReleaseType
    architecture = $sdk.Architecture
    ohosArch = $sdk.OhosArch
    targetTriple = $sdk.TargetTriple
    sysroot = $sdk.Sysroot
    toolchainFile = $sdk.ToolchainFile
    configuration = $Configuration
    sourceCommit = $sourceCommit
    sourceDirty = $sourceDirty
}
foreach ($entry in $expectedProvenance.GetEnumerator()) {
    if ([string]$provenance.($entry.Key) -ne [string]$entry.Value) {
        throw "OpenHarmony runtime provenance mismatch for '$($entry.Key)': expected '$($entry.Value)', found '$($provenance.($entry.Key))'."
    }
}

$requiredAotSdkFiles = @(
    'libaotminipal.a',
    'libbootstrapper.o',
    'libbootstrapperdll.o',
    'libeventpipe-disabled.a',
    'libeventpipe-enabled.a',
    'libRuntime.ServerGC.a',
    'libRuntime.WorkstationGC.a',
    'libstandalonegc-disabled.a',
    'libstandalonegc-enabled.a',
    'libstdc++compat.a',
    'System.Private.CoreLib.dll',
    'System.Private.Reflection.Execution.dll',
    'System.Private.StackTraceMetadata.dll',
    'System.Private.TypeLoader.dll'
)
$requiredManagedFiles = @(
    'System.dll',
    'System.Runtime.dll'
)
$requiredNativeFiles = @(
    'libSystem.Globalization.Native.so',
    'libSystem.IO.Compression.Native.so',
    'libSystem.IO.Ports.Native.so',
    'libSystem.Native.so',
    'libSystem.Security.Cryptography.Native.OpenSsl.so',
    'libicuuc.so.78',
    'libicui18n.so.78',
    'libicudata.so.78',
    'libc++_shared.so',
    'libcrypto.so.3',
    'libssl.so.3'
)

foreach ($fileName in $requiredAotSdkFiles) {
    Assert-RequiredFile -Path (Join-Path $aotSdk $fileName)
}
foreach ($fileName in $requiredManagedFiles) {
    Assert-RequiredFile -Path (Join-Path $managedOutput $fileName)
}
foreach ($fileName in $requiredNativeFiles) {
    Assert-RequiredFile -Path (Join-Path $nativeOutput $fileName)
}

$runtimeListPath = Join-Path $runtimePackRoot 'data\RuntimeList.xml'
Assert-RequiredFile -Path $runtimeListPath
$runtimeList = [xml](Get-Content -LiteralPath $runtimeListPath -Raw)
foreach ($runtimeFile in @($runtimeList.FileList.File)) {
    $runtimeFilePath = Join-Path $runtimePackRoot ($runtimeFile.Path -replace '/', '\')
    Assert-RequiredFile -Path $runtimeFilePath
}

$llvmBin = Split-Path $sdk.Clang
$readElf = Join-Path $llvmBin 'llvm-readelf.exe'
$llvmNm = Join-Path $llvmBin 'llvm-nm.exe'
Assert-RequiredFile -Path $readElf
Assert-RequiredFile -Path $llvmNm

$nativeElfFiles = @($requiredNativeFiles | ForEach-Object { Join-Path $nativeOutput $_ })
$aotElfFiles = @(Get-ChildItem -LiteralPath $aotSdk -File | Where-Object { $_.Extension -in @('.a', '.o') } | ForEach-Object FullName)
foreach ($elfPath in @($nativeElfFiles + $aotElfFiles)) {
    $header = Invoke-CheckedTool -Tool $readElf -Arguments @('-h', $elfPath)
    $machineLines = @($header | Where-Object { $_ -match '^\s*Machine:' })
    if ($machineLines.Count -eq 0) {
        throw "No ELF machine headers were found in '$elfPath'."
    }
    $wrongMachines = @($machineLines | Where-Object { $_ -notmatch "^\s*Machine:\s+$([regex]::Escape($machine))\s*$" })
    if ($wrongMachines.Count -ne 0) {
        throw "Unexpected ELF machine in '$elfPath': $($wrongMachines -join '; ')"
    }
    $classLines = @($header | Where-Object { $_ -match '^\s*Class:' })
    if ($classLines.Count -eq 0 -or ($classLines | Where-Object { $_ -notmatch '^\s*Class:\s+ELF64\s*$' }).Count -ne 0) {
        throw "Expected ELF64 input in '$elfPath'."
    }
    $dataLines = @($header | Where-Object { $_ -match '^\s*Data:' })
    if ($dataLines.Count -eq 0 -or ($dataLines | Where-Object { $_ -notmatch "^\s*Data:\s+2's complement, little endian\s*$" }).Count -ne 0) {
        throw "Expected little-endian ELF input in '$elfPath'."
    }
}

$expectedDependencies = @{
    'libSystem.Globalization.Native.so' = @('libc.so')
    'libSystem.IO.Compression.Native.so' = @('libc.so')
    'libSystem.IO.Ports.Native.so' = @('libc.so')
    'libSystem.Native.so' = @('libc.so')
    'libSystem.Security.Cryptography.Native.OpenSsl.so' = @('libc.so')
    'libicuuc.so.78' = @('libc++_shared.so', 'libc.so', 'libicudata.so.78')
    'libicui18n.so.78' = @('libc++_shared.so', 'libc.so', 'libicudata.so.78', 'libicuuc.so.78')
    'libicudata.so.78' = @('libc.so')
    'libc++_shared.so' = @('libc.so')
    'libcrypto.so.3' = @('libc.so')
    'libssl.so.3' = @('libc.so', 'libcrypto.so.3')
}
foreach ($elfPath in $nativeElfFiles) {
    $libraryName = Split-Path $elfPath -Leaf
    $dynamic = Invoke-CheckedTool -Tool $readElf -Arguments @('-d', $elfPath)
    $dynamicText = $dynamic -join [Environment]::NewLine
    if ($dynamicText -match '\(RPATH\)|\(RUNPATH\)') {
        throw "Deployment library '$elfPath' contains an unsafe RPATH or RUNPATH."
    }
    if ($dynamicText -notmatch "\(SONAME\)\s+Library soname: \[$([regex]::Escape($libraryName))\]") {
        throw "Deployment library '$elfPath' has an unexpected SONAME."
    }
    $dependencies = @($dynamic | ForEach-Object {
        if ($_ -match '\(NEEDED\)\s+Shared library: \[([^\]]+)\]') {
            $Matches[1]
        }
    } | Sort-Object -Unique)
    $expected = @($expectedDependencies[$libraryName] | Sort-Object)
    $dependencyDifferences = @(Compare-Object -ReferenceObject $expected -DifferenceObject $dependencies)
    if ($dependencyDifferences.Count -ne 0) {
        throw "Unexpected dynamic dependencies in '$elfPath': $($dependencies -join ', ')"
    }
}

$icuSymbols = @{
    'libicuuc.so.78' = 'u_strlen_78'
    'libicui18n.so.78' = 'ulocdata_getCLDRVersion_78'
}
foreach ($entry in $icuSymbols.GetEnumerator()) {
    $icuLibraryPath = Join-Path $nativeOutput $entry.Key
    $symbols = Invoke-CheckedTool -Tool $llvmNm -Arguments @('-D', '--defined-only', $icuLibraryPath)
    if (-not (($symbols -join [Environment]::NewLine) -match "\s$([regex]::Escape($entry.Value))(\s|$)")) {
        throw "Packaged ICU library '$icuLibraryPath' does not export '$($entry.Value)'."
    }
}

$entrypointPairs = @(
    @('libSystem.Globalization.Native.so', 'src\native\libs\System.Globalization.Native\entrypoints.c'),
    @('libSystem.IO.Ports.Native.so', 'src\native\libs\System.IO.Ports.Native'),
    @('libSystem.Native.so', 'src\native\libs\System.Native\entrypoints.c'),
    @('libSystem.IO.Compression.Native.so', 'src\native\libs\System.IO.Compression.Native\entrypoints.c'),
    @('libSystem.Security.Cryptography.Native.OpenSsl.so', 'src\native\libs\System.Security.Cryptography.Native\entrypoints.c')
)
foreach ($pair in $entrypointPairs) {
    $libraryPath = Join-Path $nativeOutput $pair[0]
    $entrypointsPath = Join-Path $repoRoot $pair[1]
    $entrypointsSource = if (Test-Path -LiteralPath $entrypointsPath -PathType Container) {
        (Get-ChildItem -LiteralPath $entrypointsPath -Filter '*.h' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join [Environment]::NewLine
    }
    else {
        Get-Content -LiteralPath $entrypointsPath -Raw
    }
    if ($pair[0] -eq 'libSystem.Globalization.Native.so') {
        $entrypointsSource = $entrypointsSource -replace '(?ms)^\s*#if defined\(STATIC_ICU\).*?^\s*#endif\s*', ''
        $entrypointsSource = $entrypointsSource -replace '(?ms)^\s*#if defined\(APPLE_HYBRID_GLOBALIZATION\).*?^\s*#endif\s*', ''
        $entrypointsSource = $entrypointsSource -replace '^\s*#ifndef __wasm__\s*', ''
        $entrypointsSource = $entrypointsSource -replace '^\s*#endif\s*', ''
    }
    $entrypointPattern = if ($pair[0] -eq 'libSystem.IO.Ports.Native.so') { 'PALEXPORT\s+[^;\r\n]+\s+(SystemIoPortsNative_[A-Za-z0-9_]+)\s*\(' } else { 'DllImportEntry\(([A-Za-z0-9_]+)\)' }
    $expected = @([regex]::Matches(
        $entrypointsSource,
        $entrypointPattern) |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique)
    $symbols = Invoke-CheckedTool -Tool $llvmNm -Arguments @('-D', '--defined-only', $libraryPath)
    $actual = @($symbols | ForEach-Object {
        if ($_ -match '^\s*[0-9A-Fa-f]+\s+[Tt]\s+(\S+)$') {
            ($Matches[1] -replace '@.*$', '').TrimStart('_')
        }
    } | Where-Object {
        $_ -and $_ -notin @('init', 'fini', 'etext', 'chk_fail', 'stack_chk_fail', 'PROCEDURE_LINKAGE_TABLE_')
    } | Sort-Object -Unique)
    $differences = @(Compare-Object -ReferenceObject $expected -DifferenceObject $actual)
    if ($differences.Count -ne 0) {
        $summary = @($differences | Select-Object -First 20 | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join ', '
        throw "Exported symbols in '$libraryPath' did not match '$entrypointsPath': $summary"
    }
}

Write-Output "Verified OpenHarmony API $ApiLevel $Architecture $Configuration runtime: $($aotElfFiles.Count) AOT ELF inputs, $($nativeElfFiles.Count) native libraries, and $((Get-ChildItem -LiteralPath $managedOutput -File).Count) managed files."
