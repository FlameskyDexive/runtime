[CmdletBinding()]
param(
    [string] $SdkRoot = (Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk'),

    [int] $ApiLevel = 15,

    [ValidateSet('arm64', 'x64')]
    [string] $Architecture = 'arm64',

    [ValidateSet('Debug', 'Checked', 'Release')]
    [string] $Configuration = 'Release',

    [string] $OpenSslRoot,

    [string] $IcuRoot,

    [switch] $ConfigureOnly,

    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Import-Module (Join-Path $PSScriptRoot 'OpenHarmonyBuild.psm1') -Force
$dependencyManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'dependencies.json') -Raw | ConvertFrom-Json

function Assert-DependencyMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [PSObject] $Definition,

        [string] $Architecture,

        [string] $TargetTriple
    )

    $metadataPath = Join-Path $Root 'dependency-metadata.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "OpenHarmony $Name dependency provenance was not found: '$metadataPath'. Run eng\openharmony\prepare-dependencies.ps1 first."
    }

    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $expected = [ordered]@{
        name = $Name
        version = [string]$Definition.version
        source = [string]$Definition.url
        sha256 = [string]$Definition.sha256
        license = [string]$Definition.license
        sdkApiLevel = 15
        sdkPackageVersion = [string]$dependencySdk.PackageVersion
    }
    foreach ($entry in $expected.GetEnumerator()) {
        if ([string]$metadata.($entry.Key) -ne [string]$entry.Value) {
            throw "OpenHarmony $Name dependency metadata mismatch for '$($entry.Key)' in '$metadataPath': expected '$($entry.Value)', found '$($metadata.($entry.Key))'."
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Architecture) -and $metadata.architecture -ne $Architecture) {
        throw "OpenHarmony $Name dependency architecture mismatch in '$metadataPath': expected '$Architecture', found '$($metadata.architecture)'."
    }
    if (-not [string]::IsNullOrWhiteSpace($TargetTriple) -and $metadata.targetTriple -ne $TargetTriple) {
        throw "OpenHarmony $Name dependency target triple mismatch in '$metadataPath': expected '$TargetTriple', found '$($metadata.targetTriple)'."
    }
}

$sdk = & (Join-Path $PSScriptRoot 'validate-sdk.ps1') `
    -SdkRoot $SdkRoot `
    -ApiLevel $ApiLevel `
    -Architecture $Architecture
$dependencySdk = & (Join-Path $PSScriptRoot 'validate-sdk.ps1') `
    -SdkRoot $SdkRoot `
    -ApiLevel 15 `
    -Architecture $Architecture

if ([string]::IsNullOrWhiteSpace($OpenSslRoot)) {
    $OpenSslRoot = Join-Path $repoRoot "artifacts\openharmony\dependencies\openssl\$($sdk.OhosArch)"
}

$requiredOpenSslFiles = @(
    'include\openssl\opensslv.h',
    'lib\libcrypto.a',
    'lib\libcrypto.so',
    'lib\libcrypto.so.3',
    'lib\libssl.a',
    'lib\libssl.so',
    'lib\libssl.so.3'
)
foreach ($relativePath in $requiredOpenSslFiles) {
    $fullPath = Join-Path $OpenSslRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "OpenHarmony OpenSSL dependency is incomplete: '$fullPath' was not found."
    }
}
$OpenSslRoot = (Resolve-Path -LiteralPath $OpenSslRoot).Path
Assert-DependencyMetadata `
    -Root $OpenSslRoot `
    -Name 'openssl' `
    -Definition $dependencyManifest.openssl `
    -Architecture $sdk.Architecture `
    -TargetTriple $sdk.TargetTriple

if ([string]::IsNullOrWhiteSpace($IcuRoot)) {
    $IcuRoot = Join-Path $repoRoot "artifacts\openharmony\dependencies\icu\$($dependencySdk.OhosArch)"
}

$requiredIcuFiles = @(
    'include\unicode\ucurr.h',
    'include\unicode\udata.h',
    'include\unicode\udatpg.h',
    'include\unicode\ures.h',
    'include\unicode\usearch.h',
    'lib\libicuuc.so.78',
    'lib\libicui18n.so.78',
    'lib\libicudata.so.78'
)
foreach ($relativePath in $requiredIcuFiles) {
    $fullPath = Join-Path $IcuRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "OpenHarmony ICU dependency is incomplete: '$fullPath' was not found."
    }
}
$IcuRoot = (Resolve-Path -LiteralPath $IcuRoot).Path
Assert-DependencyMetadata `
    -Root $IcuRoot `
    -Name 'icu' `
    -Definition $dependencyManifest.icu `
    -Architecture $dependencySdk.Architecture `
    -TargetTriple $dependencySdk.TargetTriple

$ridArchitecture = if ($Architecture -eq 'arm64') { 'arm64' } else { 'x64' }
$coreClrOutput = Join-Path $repoRoot "artifacts\bin\coreclr\openharmony.$Architecture.$Configuration"
$intermediatesRoot = Join-Path $repoRoot "artifacts\obj\coreclr\openharmony.$Architecture.$Configuration"
$runtimePack = Join-Path $repoRoot "artifacts\bin\microsoft.netcore.app.runtime.linux-musl-$ridArchitecture\$Configuration\runtimes\linux-musl-$ridArchitecture"
$nativeOutput = Join-Path $runtimePack 'native'

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

$sourceCommit = Get-GitValue -Arguments @('rev-parse', 'HEAD')
$sourceDirty = -not [string]::IsNullOrWhiteSpace((Get-GitValue -Arguments @('status', '--porcelain', '--untracked-files=normal')))
$expectedProvenance = [ordered]@{
    apiLevel = $sdk.ApiLevel
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

function Test-ProvenanceMatch {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject] $Actual,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Expected
    )

    foreach ($entry in $Expected.GetEnumerator()) {
        if ([string]$Actual.($entry.Key) -ne [string]$entry.Value) {
            return $false
        }
    }
    return $true
}

$intermediateProvenancePath = Join-Path $intermediatesRoot 'openharmony-build-provenance.json'
$existingProvenance = $null
if (Test-Path -LiteralPath $intermediateProvenancePath -PathType Leaf) {
    try {
        $existingProvenance = Get-Content -LiteralPath $intermediateProvenancePath -Raw | ConvertFrom-Json
    }
    catch {
        $existingProvenance = $null
    }
}

if ($null -eq $existingProvenance -or -not (Test-ProvenanceMatch -Actual $existingProvenance -Expected $expectedProvenance)) {
    foreach ($path in @($intermediatesRoot, $coreClrOutput, $runtimePack)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

$invocation = New-OpenHarmonyBuildInvocation `
    -RepoRoot $repoRoot `
    -Sdk $sdk `
    -OpenSslRoot $OpenSslRoot `
    -IcuRoot $IcuRoot `
    -Configuration $Configuration `
    -ConfigureOnly:$ConfigureOnly

if ($DryRun) {
    $invocation
    exit 0
}

Write-Host "Building .NET 10 NativeAOT for HarmonyOS API $ApiLevel ($($sdk.OhosArch), $($sdk.TargetTriple))."
Invoke-OpenHarmonyBuild -Invocation $invocation

if ($ConfigureOnly) {
    Write-Host 'OpenHarmony configure completed; runtime provenance will be written after a complete build.'
    exit 0
}

New-Item -ItemType Directory -Path $nativeOutput -Force | Out-Null
$llvmRoot = Split-Path (Split-Path $sdk.Clang)
foreach ($libraryName in @('libcrypto.so.3', 'libssl.so.3')) {
    $sourcePath = Join-Path $OpenSslRoot "lib\$libraryName"
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $nativeOutput $libraryName) -Force
}
Copy-Item -LiteralPath (Join-Path $OpenSslRoot 'LICENSE.txt') -Destination (Join-Path $nativeOutput 'OPENSSL-LICENSE.txt') -Force
foreach ($libraryName in @('libicuuc.so.78', 'libicui18n.so.78', 'libicudata.so.78', 'libc++_shared.so')) {
    $sourcePath = if ($libraryName -eq 'libc++_shared.so') {
        Join-Path $llvmRoot "lib\$($sdk.TargetTriple)\$libraryName"
    }
    else {
        Join-Path $IcuRoot "lib\$libraryName"
    }
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $nativeOutput $libraryName) -Force
}
Copy-Item -LiteralPath (Join-Path $IcuRoot 'LICENSE') -Destination (Join-Path $nativeOutput 'ICU-LICENSE.txt') -Force

$provenanceJson = $expectedProvenance | ConvertTo-Json -Depth 4
New-Item -ItemType Directory -Path $coreClrOutput -Force | Out-Null
$provenanceJson | Set-Content -LiteralPath (Join-Path $coreClrOutput 'runtime-build-provenance.json') -Encoding Ascii
New-Item -ItemType Directory -Path $intermediatesRoot -Force | Out-Null
$provenanceJson | Set-Content -LiteralPath $intermediateProvenancePath -Encoding Ascii
Write-Host "Wrote OpenHarmony runtime provenance for API $ApiLevel to '$coreClrOutput'."
