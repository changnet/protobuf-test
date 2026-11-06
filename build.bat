@echo off
rem One-click configure + build + run for the lua-protobuf vs pbc benchmark.
rem All outputs go to the build\ directory; the source tree stays clean.
rem Toolchain: VS 2022 bundled CMake/Ninja + MSVC 14.40 + Windows SDK 10.0.22621.0
setlocal EnableExtensions
cd /d "%~dp0"

set "VS=D:\Program Files\Microsoft Visual Studio\2022\Community"
set "MSVCV=14.40.33807"
set "SDKV=10.0.22621.0"
set "SDK=D:\Windows Kits\10"

set "INCLUDE=%VS%\VC\Tools\MSVC\%MSVCV%\include;%SDK%\Include\%SDKV%\ucrt;%SDK%\Include\%SDKV%\um;%SDK%\Include\%SDKV%\shared;%SDK%\Include\%SDKV%\winrt;%SDK%\Include\%SDKV%\cppwinrt"
set "LIB=%VS%\VC\Tools\MSVC\%MSVCV%\lib\x64;%SDK%\Lib\%SDKV%\ucrt\x64;%SDK%\Lib\%SDKV%\um\x64"
set "PATH=%VS%\VC\Tools\MSVC\%MSVCV%\bin\Hostx64\x64;%SDK%\bin\%SDKV%\x64;%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%"

set "CMAKE_EXE=%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

chcp 65001 >nul
"%CMAKE_EXE%" -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 exit /b 1
"%CMAKE_EXE%" --build build
if errorlevel 1 exit /b 1

if /i "%~1"=="run" (
    build\bin\bench.exe
)
if /i "%~1"=="test" (
    build\bin\bench.exe
)
endlocal
