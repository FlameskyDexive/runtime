[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SdkRoot,

    [int[]] $ApiLevels = @(15, 18, 20, 23, 26),

    [string[]] $Architectures = @('arm64', 'x64')
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$fixture = Join-Path $PSScriptRoot 'toolchain-smoke'
$runRoot = Join-Path ([IO.Path]::GetTempPath()) "dotnet-ohos-toolchain-$([guid]::NewGuid().ToString('N'))"

try {
    $rows = foreach ($apiLevel in $ApiLevels) {
        foreach ($architecture in $Architectures) {
            $sdk = & (Join-Path $repoRoot 'eng\openharmony\validate-sdk.ps1') `
                -SdkRoot $SdkRoot `
                -ApiLevel $apiLevel `
                -Architecture $architecture
            $buildDirectory = Join-Path $runRoot "$apiLevel-$architecture"
            $configureArguments = @(
                '-S', $fixture,
                '-B', $buildDirectory,
                '-G', 'Ninja',
                '-DCMAKE_BUILD_TYPE=Release',
                "-DCMAKE_TOOLCHAIN_FILE=$($sdk.ToolchainFile)",
                "-DCMAKE_SYSROOT=$($sdk.Sysroot)",
                "-DCMAKE_MAKE_PROGRAM=$($sdk.Ninja)",
                "-DOHOS_ARCH=$($sdk.OhosArch)",
                '-DOHOS_PLATFORM=OHOS',
                '-DOHOS_STL=c++_shared',
                "-DOHOS_COMPATIBLE_SDK_VERSION=$apiLevel",
                '-C', (Join-Path $repoRoot 'eng\native\openharmony.cmake')
            )

            & $sdk.CMake @configureArguments | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "CMake configure failed for API $apiLevel $architecture."
            }

            & $sdk.CMake --build $buildDirectory --config Release | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "CMake build failed for API $apiLevel $architecture."
            }

            $archive = Join-Path $buildDirectory 'libopenharmony_toolchain_smoke.a'
            $readObject = Join-Path (Split-Path $sdk.Clang) 'llvm-readobj.exe'
            $fileHeader = (& $readObject --file-headers $archive) -join [Environment]::NewLine
            $expectedFormat = if ($architecture -eq 'arm64') {
                'elf64-littleaarch64'
            } else {
                'elf64-x86-64'
            }

            if ($fileHeader -notmatch [regex]::Escape($expectedFormat)) {
                throw "Unexpected object format for API $apiLevel ${architecture}: expected $expectedFormat."
            }

            [PSCustomObject][ordered]@{
                ApiLevel = $apiLevel
                Architecture = $architecture
                OhosArch = $sdk.OhosArch
                TargetTriple = $sdk.TargetTriple
                ObjectFormat = $expectedFormat
                Result = 'PASS'
            }
        }
    }

    $rows
}
finally {
    if ((Split-Path $runRoot -Parent) -eq [IO.Path]::GetTempPath().TrimEnd('\') -and
        (Split-Path $runRoot -Leaf).StartsWith('dotnet-ohos-toolchain-', [StringComparison]::Ordinal) -and
        (Test-Path -LiteralPath $runRoot)) {
        Remove-Item -LiteralPath $runRoot -Recurse -Force
    }
}
