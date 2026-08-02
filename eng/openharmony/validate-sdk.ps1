[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SdkRoot,

    [int] $ApiLevel = 15,

    [string] $Architecture = 'arm64',

    [string] $CatalogPath = (Join-Path $PSScriptRoot 'sdk-catalog.json'),

    [switch] $WriteCatalog,

    [string] $SystemImageRoot
)

$ErrorActionPreference = 'Stop'

$supportedApis = @(13..24) + 26
$buildApis = @(13, 14, 15, 18, 20, 23, 26)
$emulatorApis = @(13..24) + 26
$nativeUnavailableApis = @(16, 17, 19, 21, 22, 24)
$excludedApis = @(25)
$nativeUnavailableReason = 'No independent Native SDK package is installable for this API; it is not processed as a build target and remains an emulator run target.'
$excludedReason = 'API 25 is intentionally unsupported because no Native SDK or system image exists.'

function Resolve-RequiredFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description was not found: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-RequiredDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Description was not found: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-Executable {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    foreach ($fileName in @("$Name.exe", $Name)) {
        $path = Join-Path $Directory $fileName
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    throw "$Description was not found under: $Directory"
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse $Description at ${Path}: $($_.Exception.Message)"
    }
}

function Write-SdkCatalog {
    param(
        [Parameter(Mandatory = $true)]
        [string] $NativeSdkRoot,

        [Parameter(Mandatory = $true)]
        [string] $ImageRoot,

        [Parameter(Mandatory = $true)]
        [string] $OutputPath
    )

    $resolvedSdkRoot = Resolve-RequiredDirectory -Path $NativeSdkRoot -Description 'HarmonyOS SDK root'
    $resolvedImageRoot = Resolve-RequiredDirectory -Path $ImageRoot -Description 'HarmonyOS system-image root'

    $nativePackages = @()
    $seenNativeApis = @{}
    foreach ($sdkFolder in Get-ChildItem -LiteralPath $resolvedSdkRoot -Directory) {
        $manifestPath = Join-Path $sdkFolder.FullName 'native\oh-uni-package.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            continue
        }

        $manifest = Read-JsonFile -Path $manifestPath -Description 'HarmonyOS Native SDK manifest'
        try {
            $manifestApi = [int]$manifest.apiVersion
        }
        catch {
            throw "HarmonyOS Native SDK manifest has an invalid apiVersion at ${manifestPath}: '$($manifest.apiVersion)'."
        }

        if ($buildApis -notcontains $manifestApi) {
            continue
        }

        if ($seenNativeApis.ContainsKey($manifestApi)) {
            throw "Duplicate Native SDK manifest for API ${manifestApi}: '$($seenNativeApis[$manifestApi])' and '$manifestPath'."
        }

        $seenNativeApis[$manifestApi] = $manifestPath
        $nativePackages += [PSCustomObject][ordered]@{
            apiLevel = $manifestApi
            sdkFolderName = $sdkFolder.Name
            version = [string]$manifest.version
            releaseType = [string]$manifest.releaseType
            manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
        }
    }

    foreach ($api in $buildApis) {
        if (-not $seenNativeApis.ContainsKey($api)) {
            throw "No Native SDK manifest was found for build API $api under '$resolvedSdkRoot'."
        }
    }
    $nativePackages = @($nativePackages | Sort-Object apiLevel)

    $systemImages = @()
    $seenImageApis = @{}
    foreach ($platformFolder in Get-ChildItem -LiteralPath $resolvedImageRoot -Directory) {
        foreach ($imageFolder in Get-ChildItem -LiteralPath $platformFolder.FullName -Directory) {
            $manifestPath = Join-Path $imageFolder.FullName 'sdk-pkg.json'
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                continue
            }

            $manifest = Read-JsonFile -Path $manifestPath -Description 'HarmonyOS system image manifest'
            try {
                $manifestApi = [int]$manifest.data.apiVersion
            }
            catch {
                throw "HarmonyOS system image manifest has an invalid data.apiVersion at ${manifestPath}: '$($manifest.data.apiVersion)'."
            }

            if ($emulatorApis -notcontains $manifestApi) {
                continue
            }

            if ($seenImageApis.ContainsKey($manifestApi)) {
                throw "Duplicate system image manifest for API ${manifestApi}: '$($seenImageApis[$manifestApi])' and '$manifestPath'."
            }

            $seenImageApis[$manifestApi] = $manifestPath
            $systemImages += [PSCustomObject][ordered]@{
                apiLevel = $manifestApi
                version = [string]$manifest.data.version
                platformVersion = [string]$manifest.data.platformVersion
                releaseType = [string]$manifest.data.releaseType
                path = [string]$manifest.data.path
                manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
            }
        }
    }

    foreach ($api in $emulatorApis) {
        if (-not $seenImageApis.ContainsKey($api)) {
            throw "No system image manifest was found for emulator API $api under '$resolvedImageRoot'."
        }
    }
    $systemImages = @($systemImages | Sort-Object apiLevel)

    $nativeUnavailable = @($nativeUnavailableApis | ForEach-Object {
        [PSCustomObject][ordered]@{
            apiLevel = $_
            reason = $nativeUnavailableReason
        }
    })
    $exclusions = @($excludedApis | ForEach-Object {
        [PSCustomObject][ordered]@{
            apiLevel = $_
            reason = $excludedReason
        }
    })

    $catalog = [ordered]@{
        schemaVersion = 1
        supportedApis = $supportedApis
        buildApis = $buildApis
        emulatorApis = $emulatorApis
        nativeUnavailableApis = $nativeUnavailableApis
        nativeUnavailable = $nativeUnavailable
        excludedApis = $excludedApis
        exclusions = $exclusions
        packages = $nativePackages
        systemImages = $systemImages
    }

    $json = $catalog | ConvertTo-Json -Depth 5
    $json = $json.Replace("`r`n", "`n") + "`n"
    if ($json -match '[^\x00-\x7F]') {
        throw 'The generated SDK catalog contains non-ASCII data.'
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    }
    [IO.File]::WriteAllText($OutputPath, $json, [Text.ASCIIEncoding]::new())
    return (Resolve-Path -LiteralPath $OutputPath).Path
}

if ($WriteCatalog) {
    if ([string]::IsNullOrWhiteSpace($SystemImageRoot)) {
        throw 'SystemImageRoot is required when WriteCatalog is specified.'
    }

    Write-SdkCatalog -NativeSdkRoot $SdkRoot -ImageRoot $SystemImageRoot -OutputPath $CatalogPath
    return
}

$resolvedCatalogPath = Resolve-RequiredFile -Path $CatalogPath -Description 'OpenHarmony SDK catalog'
$catalog = Read-JsonFile -Path $resolvedCatalogPath -Description 'OpenHarmony SDK catalog'
if ([int]$catalog.schemaVersion -ne 1) {
    throw "Unsupported OpenHarmony SDK catalog schema version '$($catalog.schemaVersion)'. Expected '1'."
}

if (@($catalog.excludedApis) -contains $ApiLevel) {
    if ($ApiLevel -eq 25) {
        throw 'API 25 is intentionally unsupported.'
    }
    throw "HarmonyOS API $ApiLevel is intentionally unsupported."
}

if (@($catalog.supportedApis) -notcontains $ApiLevel) {
    throw "Unsupported HarmonyOS API level '$ApiLevel'. Supported API levels: 13-24, 26."
}

if (@($catalog.nativeUnavailableApis) -contains $ApiLevel) {
    throw "HarmonyOS API $ApiLevel does not have an installable Native SDK and is not processed for compilation. Its system image is only an emulator/device test target."
}

$packages = @($catalog.packages | Where-Object { [int]$_.apiLevel -eq $ApiLevel })
if ($packages.Count -ne 1) {
    throw "OpenHarmony SDK catalog must contain exactly one Native SDK package for build API $ApiLevel; found $($packages.Count)."
}
$package = $packages[0]

$architectureMap = @{
    arm64 = @{
        OhosArch = 'arm64-v8a'
        TargetTriple = 'aarch64-linux-ohos'
    }
    x64 = @{
        OhosArch = 'x86_64'
        TargetTriple = 'x86_64-linux-ohos'
    }
}

if (-not $architectureMap.ContainsKey($Architecture)) {
    throw "Unsupported OpenHarmony architecture '$Architecture'. Supported architectures: arm64, x64."
}

$resolvedSdkRoot = Resolve-RequiredDirectory -Path $SdkRoot -Description 'HarmonyOS SDK root'
$sdkFolder = [string]$package.sdkFolderName
$nativeRoot = Resolve-RequiredDirectory `
    -Path (Join-Path $resolvedSdkRoot "$sdkFolder\native") `
    -Description "HarmonyOS API $ApiLevel native SDK (expected folder '$sdkFolder')"
$packageManifestPath = Resolve-RequiredFile `
    -Path (Join-Path $nativeRoot 'oh-uni-package.json') `
    -Description "HarmonyOS API $ApiLevel native package manifest"
$packageManifest = Read-JsonFile -Path $packageManifestPath -Description "HarmonyOS API $ApiLevel native package manifest"

if ([int]$packageManifest.apiVersion -ne $ApiLevel) {
    throw "HarmonyOS native package API mismatch in ${packageManifestPath}: expected '$ApiLevel', found '$($packageManifest.apiVersion)'."
}
if ([string]$packageManifest.version -cne [string]$package.version) {
    throw "HarmonyOS native package version mismatch in ${packageManifestPath}: expected '$($package.version)', found '$($packageManifest.version)'."
}
if ([string]$packageManifest.releaseType -cne [string]$package.releaseType) {
    throw "HarmonyOS native package release type mismatch in ${packageManifestPath}: expected '$($package.releaseType)', found '$($packageManifest.releaseType)'."
}

$manifestSha256 = (Get-FileHash -LiteralPath $packageManifestPath -Algorithm SHA256).Hash
if ($manifestSha256 -cne [string]$package.manifestSha256) {
    throw "HarmonyOS native package SHA256 mismatch in ${packageManifestPath}: expected '$($package.manifestSha256)', found '$manifestSha256'."
}

$llvmBin = Resolve-RequiredDirectory -Path (Join-Path $nativeRoot 'llvm\bin') -Description "HarmonyOS API $ApiLevel LLVM bin directory"
$cmakeBin = Resolve-RequiredDirectory -Path (Join-Path $nativeRoot 'build-tools\cmake\bin') -Description "HarmonyOS API $ApiLevel CMake bin directory"
$architectureValues = $architectureMap[$Architecture]

[PSCustomObject][ordered]@{
    ApiLevel = $ApiLevel
    SdkFolder = $sdkFolder
    PackageVersion = [string]$packageManifest.version
    ReleaseType = [string]$packageManifest.releaseType
    ManifestSha256 = $manifestSha256
    Architecture = $Architecture
    OhosArch = $architectureValues.OhosArch
    TargetTriple = $architectureValues.TargetTriple
    NativeRoot = $nativeRoot
    Sysroot = Resolve-RequiredDirectory -Path (Join-Path $nativeRoot 'sysroot') -Description "HarmonyOS API $ApiLevel sysroot"
    ToolchainFile = Resolve-RequiredFile -Path (Join-Path $nativeRoot 'build\cmake\ohos.toolchain.cmake') -Description "HarmonyOS API $ApiLevel CMake toolchain"
    Clang = Resolve-Executable -Directory $llvmBin -Name 'clang' -Description "HarmonyOS API $ApiLevel Clang"
    ClangXX = Resolve-Executable -Directory $llvmBin -Name 'clang++' -Description "HarmonyOS API $ApiLevel Clang++"
    Linker = Resolve-Executable -Directory $llvmBin -Name 'ld.lld' -Description "HarmonyOS API $ApiLevel LLD"
    CMake = Resolve-Executable -Directory $cmakeBin -Name 'cmake' -Description "HarmonyOS API $ApiLevel CMake"
    Ninja = Resolve-Executable -Directory $cmakeBin -Name 'ninja' -Description "HarmonyOS API $ApiLevel Ninja"
}
