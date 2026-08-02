[CmdletBinding()]
param(
    [string] $SdkRoot = (Join-Path $env:LOCALAPPDATA 'OpenHarmony\Sdk'),

    [int[]] $Apis = @(13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 26),

    [ValidateSet('arm64', 'x64')]
    [string[]] $Architectures = @('arm64', 'x64'),

    [ValidateSet('Debug', 'Checked', 'Release')]
    [string] $Configuration = 'Release',

    [switch] $ConfigureOnly,

    [string] $ArtifactsBaseRoot,

    [string] $DependencyRoot,

    [string] $BuildScriptPath = (Join-Path $PSScriptRoot 'build-runtime.ps1'),

    [string] $VerifyScriptPath = (Join-Path $PSScriptRoot 'verify-runtime.ps1'),

    [string] $CatalogPath = (Join-Path $PSScriptRoot 'sdk-catalog.json')
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
$supportedApis = @($catalog.supportedApis | ForEach-Object { [int]$_ })
$buildApis = @($catalog.packages.apiLevel | ForEach-Object { [int]$_ })
$nativeUnavailable = @{}
foreach ($entry in @($catalog.nativeUnavailable)) {
    $nativeUnavailable[[int]$entry.apiLevel] = [string]$entry.reason
}

if ($Apis -contains 25) {
    throw 'API 25 is intentionally unsupported because no compatible SDK/image is available.'
}
$unsupportedApis = @($Apis | Where-Object { $_ -notin $supportedApis } | Sort-Object -Unique)
if ($unsupportedApis.Count -ne 0) {
    throw "Unsupported OpenHarmony matrix API values: $($unsupportedApis -join ', ')."
}

if ([string]::IsNullOrWhiteSpace($ArtifactsBaseRoot)) {
    $ArtifactsBaseRoot = Join-Path $repoRoot 'artifacts\openharmony'
}
elseif (-not [IO.Path]::IsPathRooted($ArtifactsBaseRoot)) {
    $ArtifactsBaseRoot = Join-Path $repoRoot $ArtifactsBaseRoot
}
$ArtifactsBaseRoot = [IO.Path]::GetFullPath($ArtifactsBaseRoot).TrimEnd('\', '/')

if ([string]::IsNullOrWhiteSpace($DependencyRoot)) {
    $DependencyRoot = Join-Path $repoRoot 'artifacts\openharmony\dependencies'
}
elseif (-not [IO.Path]::IsPathRooted($DependencyRoot)) {
    $DependencyRoot = Join-Path $repoRoot $DependencyRoot
}
$DependencyRoot = [IO.Path]::GetFullPath($DependencyRoot).TrimEnd('\', '/')

function Write-MatrixSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string] $CaseRoot,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Summary
    )

    New-Item -ItemType Directory -Path $CaseRoot -Force | Out-Null
    $summaryPath = Join-Path $CaseRoot 'runtime-matrix-summary.json'
    ($Summary | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $summaryPath -Encoding Ascii
    return $summaryPath
}

function Get-UnresolvedSymbols {
    param(
        [Parameter(Mandatory = $true)]
        [string] $LlvmNm,

        [Parameter(Mandatory = $true)]
        [string] $NativeOutput
    )

    $symbols = foreach ($library in @(Get-ChildItem -LiteralPath $NativeOutput -File -Filter '*.so*' | Where-Object { $_.Extension -ne '.dbg' })) {
        $output = & $LlvmNm --undefined-only --just-symbol-name $library.FullName 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "llvm-nm failed for '$($library.FullName)' with exit code $LASTEXITCODE."
        }
        $output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    return @($symbols | Sort-Object -Unique)
}

foreach ($api in $Apis) {
    foreach ($architecture in $Architectures) {
        $caseRoot = Join-Path $ArtifactsBaseRoot "api$api\$architecture\$Configuration"
        $ohosArch = if ($architecture -eq 'arm64') { 'arm64-v8a' } else { 'x86_64' }
        $targetTriple = if ($architecture -eq 'arm64') { 'aarch64-linux-ohos' } else { 'x86_64-linux-ohos' }
        $summary = [ordered]@{
            schemaVersion = 1
            buildApi = $api
            runtimeBaselineApi = 13
            architecture = $architecture
            ohosArch = $ohosArch
            configuration = $Configuration
            configureOnly = [bool]$ConfigureOnly
            status = $null
            buildExitCode = $null
            elfTriple = $targetTriple
            unresolvedSymbols = @()
            provenancePath = $null
            provenanceSha256 = $null
            sourceCommit = $null
            sourceDirty = $null
            reason = $null
        }

        if ($api -notin $buildApis) {
            $summary.status = 'SKIPPED'
            $summary.reason = if ($nativeUnavailable.ContainsKey($api)) {
                $nativeUnavailable[$api]
            }
            else {
                "OpenHarmony API $api has no installable Native SDK and is not a compile target."
            }
            Write-MatrixSummary -CaseRoot $caseRoot -Summary $summary | Out-Null
            [PSCustomObject]$summary
            continue
        }

        try {
            $buildArguments = @{
                SdkRoot = $SdkRoot
                ApiLevel = $api
                Architecture = $architecture
                Configuration = $Configuration
                ArtifactsRoot = $caseRoot
                OpenSslRoot = Join-Path $DependencyRoot "openssl\$ohosArch"
                IcuRoot = Join-Path $DependencyRoot "icu\$ohosArch"
                ConfigureOnly = [bool]$ConfigureOnly
            }
            & $BuildScriptPath @buildArguments
            if ($LASTEXITCODE -notin @(0, $null)) {
                throw "OpenHarmony runtime build exited with code $LASTEXITCODE."
            }

            $provenancePath = Join-Path $caseRoot 'runtime-build-provenance.json'
            if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) {
                throw "Runtime provenance was not produced: '$provenancePath'."
            }
            $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
            if (-not $ConfigureOnly) {
                & $VerifyScriptPath `
                    -SdkRoot $SdkRoot `
                    -ApiLevel $api `
                    -Architecture $architecture `
                    -Configuration $Configuration `
                    -ArtifactsRoot $caseRoot
                if ($LASTEXITCODE -notin @(0, $null)) {
                    throw "OpenHarmony runtime verification exited with code $LASTEXITCODE."
                }
                $sdk = & (Join-Path $PSScriptRoot 'validate-sdk.ps1') `
                    -SdkRoot $SdkRoot `
                    -ApiLevel $api `
                    -Architecture $architecture
                $ridArchitecture = if ($architecture -eq 'arm64') { 'arm64' } else { 'x64' }
                $nativeOutput = Join-Path $caseRoot "bin\microsoft.netcore.app.runtime.linux-musl-$ridArchitecture\$Configuration\runtimes\linux-musl-$ridArchitecture\native"
                $llvmNm = Join-Path (Split-Path $sdk.Clang) 'llvm-nm.exe'
                $summary.unresolvedSymbols = @(Get-UnresolvedSymbols -LlvmNm $llvmNm -NativeOutput $nativeOutput)
            }

            $summary.status = if ($ConfigureOnly) { 'CONFIGURED' } else { 'PASS' }
            $summary.buildExitCode = 0
            $summary.provenancePath = $provenancePath
            $summary.provenanceSha256 = (Get-FileHash -LiteralPath $provenancePath -Algorithm SHA256).Hash
            $summary.sourceCommit = [string]$provenance.sourceCommit
            $summary.sourceDirty = [bool]$provenance.sourceDirty
            Write-MatrixSummary -CaseRoot $caseRoot -Summary $summary | Out-Null
            [PSCustomObject]$summary
        }
        catch {
            $summary.status = 'FAIL'
            $summary.buildExitCode = if ($LASTEXITCODE -is [int] -and $LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
            $summary.reason = $_.Exception.Message
            Write-MatrixSummary -CaseRoot $caseRoot -Summary $summary | Out-Null
            throw
        }
    }
}
