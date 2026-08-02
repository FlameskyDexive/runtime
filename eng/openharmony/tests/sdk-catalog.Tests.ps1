BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\validate-sdk.ps1'
    $catalogPath = Join-Path $PSScriptRoot '..\sdk-catalog.json'

$supportedApis = @(13..24) + 26
$buildApis = @(13, 14, 15, 18, 20, 23, 26)
$emulatorApis = @(13..24) + 26
$nativeUnavailableApis = @(16, 17, 19, 21, 22, 24)
$nativeUnavailableReason = 'No independent Native SDK package is installable for this API; it is not processed as a build target and remains an emulator run target.'
$excludedReason = 'API 25 is intentionally unsupported because no Native SDK or system image exists.'

$nativePackageFacts = @(
    @{ ApiLevel = 13; SdkFolderName = '13'; Version = '5.0.1.111'; ReleaseType = 'Release'; ManifestSha256 = '435560BC7D74005A306E8EA04110FC19E5392556D6B10493CC9DD93F7E7F1853' }
    @{ ApiLevel = 14; SdkFolderName = '14'; Version = '5.0.2.123'; ReleaseType = 'Release'; ManifestSha256 = '0BC0ED1C01345BBA9B453E93F5FAF4B4F55F9D17850161D58742A734E324956C' }
    @{ ApiLevel = 15; SdkFolderName = '15'; Version = '5.0.3.135'; ReleaseType = 'Release'; ManifestSha256 = '0E0DB0B79DF8A26E18B7BD17FCCED06242D66C8315822F4037A357BC211CECC8' }
    @{ ApiLevel = 18; SdkFolderName = '18'; Version = '5.1.0.107'; ReleaseType = 'Release'; ManifestSha256 = '16CAC01A0F3829A89353E7117E823DA2A5D4F3BE1E6C3250024409F39F85F987' }
    @{ ApiLevel = 20; SdkFolderName = '20'; Version = '6.0.0.47'; ReleaseType = 'Release'; ManifestSha256 = 'E7D4E0F7970EC5D8430F2935DC22B31EFFE06D9E8C725A16FF0706F8C60EC22C' }
    @{ ApiLevel = 23; SdkFolderName = '23'; Version = '6.1.0.32'; ReleaseType = 'Release'; ManifestSha256 = '475FA68431FCEA117512CCEA5BF303D0FA6BD9A2C2E4C6DCBE6567FD1CED3B44' }
    @{ ApiLevel = 26; SdkFolderName = '26.0.0'; Version = '26.0.0.25'; ReleaseType = 'Beta'; ManifestSha256 = 'EE77347D990B6F99C07777993FB372E5FB55AA08E76A4C82E3253F8F9E094B16' }
)

$systemImageFacts = @(
    @{ ApiLevel = 13; Version = '5.0.0.112'; PlatformVersion = '5.0.1'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-5.0.1,phone_x86'; ManifestSha256 = 'A1FB8B030BAC49412FC72D60FD4EC208148C598E7B82ADD5092FAA064AAF85F7' }
    @{ ApiLevel = 14; Version = '5.0.0.124'; PlatformVersion = '5.0.2'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-5.0.2,phone_x86'; ManifestSha256 = 'C4754CE173171413203F9E926664D92F6BA2A4909CA9BE6FFBFD2B9F8353A359' }
    @{ ApiLevel = 15; Version = '5.0.0.135'; PlatformVersion = '5.0.3'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-5.0.3,phone_x86'; ManifestSha256 = 'E4FB6479745D889552CD9D81F29C4802728B6A2F1F6B0F3B9F0FEB919C1CBD9A' }
    @{ ApiLevel = 16; Version = '5.0.0.150'; PlatformVersion = '5.0.4'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-5.0.4,phone_x86'; ManifestSha256 = '301BACB4EB3BF3C5C9FBA50D3EF226CCCFDD070C49AC182CF452B2E79899F9C6' }
    @{ ApiLevel = 17; Version = '5.0.1.121'; PlatformVersion = '5.0.5'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-5.0.5,phone_x86'; ManifestSha256 = '95929A43722F2B6D7FB6D946475D77A3905F07251446F1C746FD921AFB649941' }
    @{ ApiLevel = 18; Version = '5.1.0.110'; PlatformVersion = '5.1.0'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-5.1.0,phone_all_x86'; ManifestSha256 = '462AEEC3FEBBCB986D4A977D93C22C02B64C592B24E2833C58F94C90643DC91F' }
    @{ ApiLevel = 19; Version = '5.1.0.235'; PlatformVersion = '5.1.1'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-5.1.1,phone_all_x86'; ManifestSha256 = 'CB70E7AF153AD0A5F9808DB4276FC9EE169991085B0AB08DCD6B871899B6B8A2' }
    @{ ApiLevel = 20; Version = '6.0.0.48'; PlatformVersion = '6.0.0'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-6.0.0,phone_all_x86'; ManifestSha256 = '083A1DD44FDFA8773B3BAF1A14FCACB8B808B242A72F11A0B350B4B385462256' }
    @{ ApiLevel = 21; Version = '6.0.0.112'; PlatformVersion = '6.0.1'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-6.0.1,phone_all_x86'; ManifestSha256 = '08956D923EB27F1874ABA46307223D05384FE8F4D305F403FABF724B46E67825' }
    @{ ApiLevel = 22; Version = '6.0.0.130'; PlatformVersion = '6.0.2'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-6.0.2,phone_all_x86'; ManifestSha256 = 'D4BBB37E0288E2FCA88DF2E3FB1FACE1B8894131CB6CF6680CB37A86DE809ADA' }
    @{ ApiLevel = 23; Version = '6.1.0.115'; PlatformVersion = '6.1.0'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-6.0.31,phone_all_x86'; ManifestSha256 = 'FEB8D741AFFFAA310EC4F7616736DF93E23A4DD52C5E3A0E752FDCD5FB552F66' }
    @{ ApiLevel = 24; Version = '6.1.0.125'; PlatformVersion = '6.1.1'; ReleaseType = 'Release'; Path = 'system-image,HarmonyOS-6.1.1,phone_all_x86'; ManifestSha256 = '68A166D5FCDF1297C06342C3BBFF0831D06A9811B5C501413AC9047A5FA767D2' }
    @{ ApiLevel = 26; Version = '7.0.0.32'; PlatformVersion = '26.0.0'; ReleaseType = 'Beta2'; Path = 'system-image,HarmonyOS-7.0.0,phone_all_x86'; ManifestSha256 = 'BAE7B713FEF4B411E79687B998200A208EE0B1F2A175408F8028433E135B9E6F' }
)

function New-NativeManifest {
    param(
        [Parameter(Mandatory = $true)] [string] $Root,
        [Parameter(Mandatory = $true)] [string] $Folder,
        [Parameter(Mandatory = $true)] [int] $ApiLevel,
        [string] $Version = "test-$ApiLevel",
        [string] $ReleaseType = 'Release'
    )

    $manifestPath = Join-Path $Root "$Folder\native\oh-uni-package.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $manifestPath) | Out-Null
    [ordered]@{
        apiVersion = "$ApiLevel"
        path = 'native'
        releaseType = $ReleaseType
        version = $Version
    } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
}

function New-SystemImageManifest {
    param(
        [Parameter(Mandatory = $true)] [string] $Root,
        [Parameter(Mandatory = $true)] [string] $PlatformFolder,
        [Parameter(Mandatory = $true)] [int] $ApiLevel
    )

    $imageFolder = if ($ApiLevel -lt 18) { 'phone_x86' } else { 'phone_all_x86' }
    $manifestPath = Join-Path $Root "$PlatformFolder\$imageFolder\sdk-pkg.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $manifestPath) | Out-Null
    [ordered]@{
        meta = [ordered]@{ version = '1.0.0' }
        data = [ordered]@{
            apiVersion = "$ApiLevel"
            displayName = 'System-image-phone'
            path = "system-image,$PlatformFolder,$imageFolder"
            platformVersion = "platform-$ApiLevel"
            releaseType = if ($ApiLevel -eq 26) { 'Beta2' } else { 'Release' }
            version = "image-$ApiLevel"
        }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
}

function New-CompleteCatalogInput {
    param(
        [Parameter(Mandatory = $true)] [string] $SdkRoot,
        [Parameter(Mandatory = $true)] [string] $SystemImageRoot
    )

    foreach ($package in $nativePackageFacts) {
        New-NativeManifest `
            -Root $SdkRoot `
            -Folder $package.SdkFolderName `
            -ApiLevel $package.ApiLevel `
            -Version $package.Version `
            -ReleaseType $package.ReleaseType
    }

    foreach ($api in $emulatorApis) {
        New-SystemImageManifest -Root $SystemImageRoot -PlatformFolder "HarmonyOS-$api" -ApiLevel $api
    }
}
}

Describe 'checked-in OpenHarmony SDK catalog' {
    BeforeAll {
        $catalogText = Get-Content -Raw -LiteralPath $catalogPath
        $catalog = $catalogText | ConvertFrom-Json
    }

    It 'uses schema version 1 and ASCII JSON' {
        $catalog.schemaVersion | Should -Be 1
        ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($catalogPath))) | Should -BeExactly $catalogText
    }

    It 'separates supported, build, emulator, unavailable, and excluded API sets' {
        @($catalog.supportedApis) | Should -Be $supportedApis
        @($catalog.buildApis) | Should -Be $buildApis
        @($catalog.emulatorApis) | Should -Be $emulatorApis
        @($catalog.nativeUnavailableApis) | Should -Be $nativeUnavailableApis
        @($catalog.excludedApis) | Should -Be @(25)
    }

    It 'explains every native-unavailable and excluded API in the catalog' {
        @($catalog.nativeUnavailable).Count | Should -Be $nativeUnavailableApis.Count
        @($catalog.nativeUnavailable.apiLevel) | Should -Be $nativeUnavailableApis
        foreach ($entry in $catalog.nativeUnavailable) {
            $entry.reason | Should -BeExactly $nativeUnavailableReason
        }

        @($catalog.exclusions).Count | Should -Be 1
        $catalog.exclusions[0].apiLevel | Should -Be 25
        $catalog.exclusions[0].reason | Should -BeExactly $excludedReason
    }

    It 'records the exact installable Native SDK package facts in API order' {
        @($catalog.packages).Count | Should -Be $nativePackageFacts.Count

        for ($index = 0; $index -lt $nativePackageFacts.Count; $index++) {
            $actual = $catalog.packages[$index]
            $expected = $nativePackageFacts[$index]
            $actual.apiLevel | Should -Be $expected.ApiLevel
            $actual.sdkFolderName | Should -BeExactly $expected.SdkFolderName
            $actual.version | Should -BeExactly $expected.Version
            $actual.releaseType | Should -BeExactly $expected.ReleaseType
            $actual.manifestSha256 | Should -BeExactly $expected.ManifestSha256
        }
    }

    It 'records the exact x86 system image facts in API order' {
        @($catalog.systemImages).Count | Should -Be $systemImageFacts.Count

        for ($index = 0; $index -lt $systemImageFacts.Count; $index++) {
            $actual = $catalog.systemImages[$index]
            $expected = $systemImageFacts[$index]
            $actual.apiLevel | Should -Be $expected.ApiLevel
            $actual.version | Should -BeExactly $expected.Version
            $actual.platformVersion | Should -BeExactly $expected.PlatformVersion
            $actual.releaseType | Should -BeExactly $expected.ReleaseType
            $actual.path | Should -BeExactly $expected.Path
            $actual.manifestSha256 | Should -BeExactly $expected.ManifestSha256
        }
    }

    It 'does not include API 12 or API 25 as a package or system image' {
        @($catalog.packages.apiLevel) | Should -Not -Contain 12
        @($catalog.packages.apiLevel) | Should -Not -Contain 25
        @($catalog.systemImages.apiLevel) | Should -Not -Contain 12
        @($catalog.systemImages.apiLevel) | Should -Not -Contain 25
    }
}

Describe 'OpenHarmony SDK catalog generation' {
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        $sdkRoot = Join-Path $caseRoot 'Sdk'
        $systemImageRoot = Join-Path $caseRoot 'system-image'
        $generatedCatalog = Join-Path $caseRoot 'sdk-catalog.json'
        New-CompleteCatalogInput -SdkRoot $sdkRoot -SystemImageRoot $systemImageRoot
    }

    It 'generates sorted deterministic ASCII JSON and ignores API 12' {
        New-NativeManifest -Root $sdkRoot -Folder '12' -ApiLevel 12
        New-SystemImageManifest -Root $systemImageRoot -PlatformFolder 'HarmonyOS-4.1.0' -ApiLevel 12

        & $scriptPath -SdkRoot $sdkRoot -WriteCatalog -CatalogPath $generatedCatalog -SystemImageRoot $systemImageRoot
        $firstBytes = [IO.File]::ReadAllBytes($generatedCatalog)
        $firstText = [Text.Encoding]::ASCII.GetString($firstBytes)
        $first = $firstText | ConvertFrom-Json

        & $scriptPath -SdkRoot $sdkRoot -WriteCatalog -CatalogPath $generatedCatalog -SystemImageRoot $systemImageRoot
        $secondBytes = [IO.File]::ReadAllBytes($generatedCatalog)

        [Convert]::ToBase64String($secondBytes) | Should -BeExactly ([Convert]::ToBase64String($firstBytes))
        @($first.packages.apiLevel) | Should -Be $buildApis
        @($first.systemImages.apiLevel) | Should -Be $emulatorApis
        @($first.nativeUnavailable.apiLevel) | Should -Be $nativeUnavailableApis
        $first.nativeUnavailable[0].reason | Should -BeExactly $nativeUnavailableReason
        $first.exclusions[0].reason | Should -BeExactly $excludedReason
        $first.packages[0].version | Should -BeExactly '5.0.1.111'
        $first.packages[-1].releaseType | Should -BeExactly 'Beta'
        $first.systemImages[0].version | Should -BeExactly 'image-13'
        $first.systemImages[0].platformVersion | Should -BeExactly 'platform-13'
        $firstText | Should -Not -Match '[^\x00-\x7F]'
    }

    It 'rejects duplicate target Native API manifests' {
        New-NativeManifest -Root $sdkRoot -Folder 'duplicate-13' -ApiLevel 13

        { & $scriptPath -SdkRoot $sdkRoot -WriteCatalog -CatalogPath $generatedCatalog -SystemImageRoot $systemImageRoot } |
            Should -Throw '*Duplicate Native SDK manifest for API 13*'
    }

    It 'rejects duplicate target system image API manifests' {
        New-SystemImageManifest -Root $systemImageRoot -PlatformFolder 'HarmonyOS-duplicate-13' -ApiLevel 13

        { & $scriptPath -SdkRoot $sdkRoot -WriteCatalog -CatalogPath $generatedCatalog -SystemImageRoot $systemImageRoot } |
            Should -Throw '*Duplicate system image manifest for API 13*'
    }
}
