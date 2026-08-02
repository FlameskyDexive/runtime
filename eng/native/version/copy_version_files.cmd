@if not defined _echo @echo off
setlocal EnableDelayedExpansion EnableExtensions

set "__VersionFolder=%~dp0"
set "__RepoRoot=%~dp0..\..\.."
:: normalize
for %%i in ("%__RepoRoot%") do set "__RepoRoot=%%~fi"
if not defined __ArtifactsObjDir set "__ArtifactsObjDir=%__RepoRoot%\artifacts\obj"
if not exist "%__ArtifactsObjDir%" md "%__ArtifactsObjDir%"

for /r "%__VersionFolder%" %%a in (*.h *.rc) do (
    if not exist "%__artifactsObjDir%\%%~nxa" (
        copy "%%a" "%__artifactsObjDir%"
    )
)
