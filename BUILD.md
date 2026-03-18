# Building OTClientV8 from source (Windows)

Follow the [official README](https://github.com/OTCv8/otcv8-dev) and the steps below.

## Requirements (from README)

1. **Visual Studio 2019** (Community or Build Tools) with workload **"Desktop development with C++"**  
   - The project and vcpkg commit used here target VS 2019. Using VS 2022 can cause vcpkg to report *"Unable to find a valid Visual Studio instance"*.
   - [VS 2019 downloads](https://visualstudio.microsoft.com/vs/older-downloads/)

2. **vcpkg** at commit `3b3bd424827a1f7f4813216f6b32b6c61e386b2e`  
   - [Direct zip](https://github.com/microsoft/vcpkg/archive/3b3bd424827a1f7f4813216f6b32b6c61e386b2e.zip)  
   - Extract as `vcpkg` in this folder (same folder as `build_from_source.bat`), then run `bootstrap-vcpkg.bat` inside `vcpkg`.

## Steps

### Option A: Automated script

1. Ensure **VS 2019** is installed and vcpkg is at the commit above and bootstrapped.
2. Open **x86 Native Tools Command Prompt for VS 2019** (Start → Visual Studio 2019 → x86 Native Tools Command Prompt).
3. Run:
   ```bat
   cd /d c:\Users\Augusto\Downloads\otcv8-dev-master
   build_from_source.bat
   ```
4. Output executables: `otclient_gl.exe` and `otclient_dx.exe` in this folder.

### Option B: Manual (from README)

1. Open **x86 Native Tools Command Prompt for VS 2019**.
2. Install dependencies (one line from README):
   ```bat
   cd /d c:\Users\Augusto\Downloads\otcv8-dev-master\vcpkg
   vcpkg install boost-iostreams:x86-windows-static boost-asio:x86-windows-static boost-beast:x86-windows-static boost-system:x86-windows-static boost-variant:x86-windows-static boost-lockfree:x86-windows-static boost-process:x86-windows-static boost-program-options:x86-windows-static luajit:x86-windows-static glew:x86-windows-static boost-filesystem:x86-windows-static boost-uuid:x86-windows-static physfs:x86-windows-static openal-soft:x86-windows-static libogg:x86-windows-static libvorbis:x86-windows-static zlib:x86-windows-static libzip:x86-windows-static openssl:x86-windows-static
   ```
3. Integrate vcpkg with MSBuild:
   ```bat
   vcpkg integrate install
   ```
4. Build:
   ```bat
   cd /d c:\Users\Augusto\Downloads\otcv8-dev-master\vc16
   MSBuild otclient.sln /p:Configuration=OpenGL /p:Platform=Win32 /m
   MSBuild otclient.sln /p:Configuration=DirectX /p:Platform=Win32 /m
   ```

## If you only have VS 2022

The README and the pinned vcpkg commit are for **VS 2019**. With VS 2022 you may get:

```text
Error: in triplet x86-windows-static: Unable to find a valid Visual Studio instance
```

**Options:**

- Install **Visual Studio 2019** (can coexist with 2022) and use the steps above, or  
- Use the [GitHub Actions build](https://github.com/OTCv8/otcv8-dev/actions) (Actions tab → run workflow or download artifacts) to get built binaries.
