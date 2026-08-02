function New-OpenHarmonyBuildInvocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepoRoot,

        [Parameter(Mandatory = $true)]
        [PSObject] $Sdk,

        [Parameter(Mandatory = $true)]
        [string] $OpenSslRoot,

        [Parameter(Mandatory = $true)]
        [string] $IcuRoot,

        [ValidateSet('Debug', 'Checked', 'Release')]
        [string] $Configuration = 'Release',

        [switch] $ConfigureOnly
    )

    $arguments = @(
        'clr.nativeaotruntime+clr.nativeaotlibs+libs',
        '-configuration', $Configuration,
        '-arch', [string]$Sdk.Architecture,
        '-cross',
        '-os', 'openharmony',
        '-ninja',
        '-verbosity', 'minimal',
        "/p:OpenHarmonyApiLevel=$($Sdk.ApiLevel)",
        "/p:OpenHarmonySdkRoot=$($Sdk.NativeRoot)",
        '/p:PortableBuild=true',
        '/p:FeatureXplatEventSource=false'
    )

    if ($ConfigureOnly) {
        $arguments += '/p:ConfigureOnly=true'
    }

    $llvmBin = Split-Path $Sdk.Clang
    $cmakeBin = Split-Path $Sdk.CMake
    $pathValue = "$cmakeBin$([IO.Path]::PathSeparator)$llvmBin$([IO.Path]::PathSeparator)$env:PATH"

    [PSCustomObject][ordered]@{
        Command = Join-Path $RepoRoot 'build.cmd'
        WorkingDirectory = $RepoRoot
        Arguments = $arguments
        Environment = [ordered]@{
            OHOS_API_LEVEL = [string]$Sdk.ApiLevel
            OHOS_ARCH = [string]$Sdk.OhosArch
            OHOS_TARGET_TRIPLE = [string]$Sdk.TargetTriple
            OHOS_NATIVE_ROOT = [string]$Sdk.NativeRoot
            OHOS_SYSROOT = [string]$Sdk.Sysroot
            OHOS_TOOLCHAIN_FILE = [string]$Sdk.ToolchainFile
            OHOS_OPENSSL_ROOT = $OpenSslRoot
            OHOS_ICU_ROOT = $IcuRoot
            TARGET_BUILD_ARCH = [string]$Sdk.Architecture
            OHOS_CLANG = [string]$Sdk.Clang
            OHOS_CLANGXX = [string]$Sdk.ClangXX
            OHOS_LLD = [string]$Sdk.Linker
            OHOS_NINJA = [string]$Sdk.Ninja
            CMakePath = [string]$Sdk.CMake
            __Ninja__ = '1'
            PATH = $pathValue
        }
        RemoveEnvironment = @('ROOTFS_DIR')
    }
}

function Get-OpenHarmonyInjectedSharedDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $CMakeCachePath
    )

    if (-not (Test-Path -LiteralPath $CMakeCachePath -PathType Leaf)) {
        throw "OpenHarmony native CMake cache was not found: '$CMakeCachePath'."
    }

    $prefix = 'CMAKE_SHARED_LINKER_FLAGS:'
    $entries = @(Get-Content -LiteralPath $CMakeCachePath | Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) })
    if ($entries.Count -ne 1) {
        throw "Expected exactly one CMAKE_SHARED_LINKER_FLAGS entry in '$CMakeCachePath'; found $($entries.Count)."
    }

    $separator = $entries[0].IndexOf('=', [StringComparison]::Ordinal)
    if ($separator -lt 0) {
        throw "Malformed CMAKE_SHARED_LINKER_FLAGS entry in '$CMakeCachePath'."
    }

    $tokens = @(($entries[0].Substring($separator + 1) -split '\s+') | ForEach-Object { $_.Trim('"', "'") })
    $knownDependencies = [ordered]@{
        '-ldeviceinfo_ndk.z' = 'libdeviceinfo_ndk.z.so'
    }
    foreach ($entry in $knownDependencies.GetEnumerator()) {
        if ($tokens -contains $entry.Key) {
            $entry.Value
        }
    }
}

function Invoke-OpenHarmonyBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject] $Invocation
    )

    $originalEnvironment = @{}
    $environmentNames = @($Invocation.Environment.Keys) + @($Invocation.RemoveEnvironment) |
        Sort-Object -Unique

    foreach ($name in $environmentNames) {
        $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }

    try {
        foreach ($name in $Invocation.RemoveEnvironment) {
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
        foreach ($entry in $Invocation.Environment.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
        }

        Push-Location $Invocation.WorkingDirectory
        try {
            & $Invocation.Command @($Invocation.Arguments)
            if ($LASTEXITCODE -ne 0) {
                throw "OpenHarmony runtime build failed with exit code $LASTEXITCODE."
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
}

Export-ModuleMember -Function New-OpenHarmonyBuildInvocation, Invoke-OpenHarmonyBuild, Get-OpenHarmonyInjectedSharedDependencies
