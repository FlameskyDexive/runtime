$script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

Describe 'OpenHarmony NativeAOT thunk and PAL contracts' {
    It 'initializes every .NET10 thunk mapping out parameter and reports E_POINTER' {
        $source = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\nativeaot\Runtime\ThunksMapping.cpp') -Raw

        ([regex]::Matches($source, 'if \(ppThunksSection == nullptr\)')).Count | Should -Be 3
        ([regex]::Matches($source, '\*ppThunksSection = nullptr;')).Count | Should -Be 3
        $source | Should -Match 'return E_POINTER;'
        $source | Should -Not -Match '#ifndef TARGET_APPLE \|\| TARGET_OPENHARMONY'
    }

    It 'uses page protection and instruction-cache primitives in the Unix PAL' {
        $source = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\nativeaot\Runtime\unix\PalUnix.cpp') -Raw

        $source | Should -Match '\bmmap\s*\('
        $source | Should -Match '\bmprotect\s*\('
        $source | Should -Match '__builtin___clear_cache'
        $source | Should -Match 'ALIGN_DOWN\('
        $source | Should -Match 'ALIGN_UP\('
    }

    It 'uses precompiled arm64 thunks instead of anonymous executable memory on OpenHarmony' {
        $cmake = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\nativeaot\Runtime\Full\CMakeLists.txt') -Raw
        $arm64 = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\nativeaot\Runtime\arm64\ThunkPoolThunks.S') -Raw
        $amd64 = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\nativeaot\Runtime\amd64\ThunkPoolThunks.S') -Raw

        $cmake | Should -Match 'if \(CLR_CMAKE_TARGET_APPLE OR CLR_CMAKE_TARGET_OPENHARMONY\)'
        $cmake | Should -Match 'ThunkPoolThunks\.\$\{ASM_SUFFIX\}'
        $arm64 | Should -Match '#elif defined\(TARGET_OPENHARMONY\)[\s\S]*#define PAGE_SIZE 0x1000[\s\S]*#define PAGE_SIZE_LOG2 12'
        $arm64 | Should -Match '#if defined\(TARGET_APPLE\) \|\| defined\(TARGET_OPENHARMONY\)[\s\S]*PATCH_LABEL ThunkPool'
        $arm64 | Should -Match '#elif defined\(TARGET_OPENHARMONY\)[\s\S]*adr\s+x0, C_FUNC\(ThunkPool\)'
        $arm64 | Should -Match '#ifdef TARGET_OPENHARMONY\s*\.zero THUNKS_MAP_SIZE\s*\.p2align PAGE_SIZE_LOG2\s*#endif'
        $amd64 | Should -Match '#if defined\(TARGET_APPLE\) \|\| defined\(TARGET_OPENHARMONY\)[\s\S]*PATCH_LABEL ThunkPool'
        $amd64 | Should -Match '#ifdef TARGET_OPENHARMONY\s*\.zero THUNKS_MAP_SIZE\s*\.p2align PAGE_SIZE_LOG2\s*#endif'
    }
}
