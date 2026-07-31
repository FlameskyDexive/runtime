$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

Describe 'OpenHarmony NativeAOT thunk and PAL contracts' {
    It 'initializes every .NET10 thunk mapping out parameter and reports E_POINTER' {
        $source = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\nativeaot\Runtime\ThunksMapping.cpp') -Raw

        ([regex]::Matches($source, 'if \(ppThunksSection == nullptr\)')).Count | Should Be 3
        ([regex]::Matches($source, '\*ppThunksSection = nullptr;')).Count | Should Be 3
        $source | Should Match 'return E_POINTER;'
        $source | Should Not Match '#ifndef TARGET_APPLE \|\| TARGET_OPENHARMONY'
    }

    It 'uses page protection and instruction-cache primitives in the Unix PAL' {
        $source = Get-Content -LiteralPath (Join-Path $repoRoot 'src\coreclr\nativeaot\Runtime\unix\PalUnix.cpp') -Raw

        $source | Should Match '\bmmap\s*\('
        $source | Should Match '\bmprotect\s*\('
        $source | Should Match '__builtin___clear_cache'
        $source | Should Match 'ALIGN_DOWN\('
        $source | Should Match 'ALIGN_UP\('
    }
}
