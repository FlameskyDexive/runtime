[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SdkRoot,

    [int] $ApiLevel = 15,

    [string] $Architecture = 'arm64'
)

$ErrorActionPreference = 'Stop'

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

$apiFolders = @{
    15 = '15'
    18 = '18'
    20 = '20'
    23 = '23'
    26 = '26.0.0'
}

if (-not $apiFolders.ContainsKey($ApiLevel)) {
    throw "Unsupported HarmonyOS API level '$ApiLevel'. Supported API levels: 15, 18, 20, 23, 26."
}

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
$sdkFolder = $apiFolders[$ApiLevel]
$nativeRoot = Resolve-RequiredDirectory -Path (Join-Path $resolvedSdkRoot "$sdkFolder\native") -Description "HarmonyOS API $ApiLevel native SDK"
$packageManifestPath = Resolve-RequiredFile -Path (Join-Path $nativeRoot 'oh-uni-package.json') -Description "HarmonyOS API $ApiLevel native package manifest"
$packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json

if ([int]$packageManifest.apiVersion -ne $ApiLevel) {
    throw "HarmonyOS native package API mismatch in ${packageManifestPath}: expected '$ApiLevel', found '$($packageManifest.apiVersion)'."
}

$llvmBin = Resolve-RequiredDirectory -Path (Join-Path $nativeRoot 'llvm\bin') -Description "HarmonyOS API $ApiLevel LLVM bin directory"
$cmakeBin = Resolve-RequiredDirectory -Path (Join-Path $nativeRoot 'build-tools\cmake\bin') -Description "HarmonyOS API $ApiLevel CMake bin directory"
$architectureValues = $architectureMap[$Architecture]

[PSCustomObject][ordered]@{
    ApiLevel = $ApiLevel
    SdkFolder = $sdkFolder
    PackageVersion = [string]$packageManifest.version
    ReleaseType = [string]$packageManifest.releaseType
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
