@echo off
setlocal
set "VCPKG_ROOT=%~dp0vcpkg"
REM README requires Visual Studio 2019 (vcpkg commit 3b3bd42 targets VS2019)
set "VS_PATH="
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat" set "VS_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community"
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" set "VS_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\Community"
if not defined VS_PATH (
  echo ERROR: Visual Studio not found. README requires VS 2019 with "Desktop development with C++".
  echo Install: https://visualstudio.microsoft.com/vs/older-downloads/ ^(2019^)
  exit /b 1
)

echo [1/4] Initializing Visual Studio x86 environment...
call "%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat" x86
if errorlevel 1 ( echo vcvarsall failed. & exit /b 1 )

echo [2/4] Installing vcpkg dependencies ^(README: x86-windows-static^). May take 30-60 min...
cd /d "%~dp0vcpkg"
vcpkg install boost-iostreams:x86-windows-static boost-asio:x86-windows-static boost-beast:x86-windows-static boost-system:x86-windows-static boost-variant:x86-windows-static boost-lockfree:x86-windows-static boost-process:x86-windows-static boost-program-options:x86-windows-static luajit:x86-windows-static glew:x86-windows-static boost-filesystem:x86-windows-static boost-uuid:x86-windows-static physfs:x86-windows-static openal-soft:x86-windows-static libogg:x86-windows-static libvorbis:x86-windows-static zlib:x86-windows-static libzip:x86-windows-static openssl:x86-windows-static
if errorlevel 1 ( echo vcpkg install failed. & exit /b 1 )

echo [3/4] Integrating vcpkg with MSBuild...
vcpkg integrate install
if errorlevel 1 ( echo vcpkg integrate failed. & exit /b 1 )

echo [4/4] Building OTClient (OpenGL and DirectX)...
cd /d "%~dp0vc16"
MSBuild otclient.sln /p:Configuration=OpenGL /p:Platform=Win32 /p:BUILD_REVISION=0 /m
if errorlevel 1 ( echo OpenGL build failed. & exit /b 1 )
MSBuild otclient.sln /p:Configuration=DirectX /p:Platform=Win32 /p:BUILD_REVISION=0 /m
if errorlevel 1 ( echo DirectX build failed. & exit /b 1 )

echo.
echo Build complete. Executables are in: %~dp0
dir /b "%~dp0otclient_gl.exe" "%~dp0otclient_dx.exe" 2>nul
endlocal
exit /b 0
