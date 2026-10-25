param(
    [string]$VsDevCmd = 'D:/Program Files/Microsoft Visual Studio/18/Community/Common7/Tools/VsDevCmd.bat',
    [string]$Cmake = 'D:/CMakeInstall/bin/cmake.exe',
    [string]$Ninja = (Join-Path $env:USERPROFILE '.cmake-deps/ninja/win/x64/ninja.exe')
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
foreach ($toolPath in @($VsDevCmd, $Cmake, $Ninja)) {
    if (!(Test-Path -LiteralPath $toolPath -PathType Leaf)) { throw "Tool not found: $toolPath" }
}
$buildRoot = Join-Path $projectRoot 'tmp/core-engines/native-font-rc'
$dependencyPath = Join-Path $buildRoot 'header-dependencies.txt'
$ctest = Join-Path (Split-Path $Cmake) 'ctest.exe'
if (!(Test-Path -LiteralPath $ctest -PathType Leaf)) { throw "Tool not found: $ctest" }
$commandPath = Join-Path $projectRoot 'tmp/core-engines/run-native-font-rc.cmd'
New-Item -ItemType Directory -Force -Path (Split-Path $commandPath) | Out-Null
# Configure and compile under the SAME code page. Otherwise MSVC /showIncludes
# can disagree with CMake's saved prefix and Ninja silently records zero headers.
$commands = @"
@echo off
chcp 65001 >nul
set "VSLANG=1033"
call "$VsDevCmd" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b 1
"$Cmake" -S "$projectRoot/entry/src/main/cpp/tests" -B "$buildRoot" -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_MAKE_PROGRAM="$Ninja"
if errorlevel 1 exit /b 1
"$Cmake" --build "$buildRoot" --target all hdm_jpeg_pdf_tests hdm_jpeg_pdf_cli --parallel 6
if errorlevel 1 exit /b 1
"$Cmake" -E chdir "$buildRoot" "$Ninja" -t deps CMakeFiles/hdm_runtime_tests.dir/runtime_tests.cpp.obj > "$dependencyPath"
findstr /c:"converter.h" "$dependencyPath" >nul
if errorlevel 1 exit /b 2
"$Cmake" -E chdir "$buildRoot" "$ctest" --output-on-failure
exit /b %errorlevel%
"@
[System.IO.File]::WriteAllText($commandPath, $commands, [System.Text.UTF8Encoding]::new($false))
& cmd.exe /d /c $commandPath
if ($LASTEXITCODE -ne 0) { throw "Native checks failed (exit $LASTEXITCODE). Do not use the older native-build cache." }
