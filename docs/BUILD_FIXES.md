# Build fixes (OTCv8 Windows / vcpkg)

Summary of changes made so local **Windows (Win32)** builds and **GitHub Actions** work with the pinned vcpkg commit `3b3bd424827a1f7f4813216f6b32b6c61e386b2e`.

---

## 1. `VCPKG_ROOT` must point at this repo’s vcpkg

If another vcpkg install exists (e.g. `C:\vcpkg`) and **`VCPKG_ROOT`** is set globally, `vcpkg.exe` may use **that** tree’s ports instead of `.\vcpkg\` in this repo, causing errors like *port directory does not exist*.

**Fix (PowerShell, before `vcpkg install` / build):**

```powershell
$env:VCPKG_ROOT = "C:\path\to\otcv8-dev-master\vcpkg"
```

Then run `.\vcpkg.exe integrate install` from that same folder so MSBuild resolves **`x86-windows-static`** packages correctly.

---

## 2. MSYS2 pkg-config downloads (404) — **mandatory vcpkg script fix**

The pinned vcpkg asks MSYS2 for **32-bit pkg-config** using URLs under:

`https://repo.msys2.org/mingw/i686/...`

Those packages were removed/rehosted; mirrors return **404**, so ports that run **`vcpkg_fixup_pkgconfig`** (e.g. **bzip2**) fail.

**Fix:** Update **`vcpkg\scripts\cmake\vcpkg_find_acquire_program.cmake`** in the **PKGCONFIG / Windows** block:

| Item | Old | New |
|------|-----|-----|
| Path segment | `mingw/i686/` | `mingw/mingw32/` |
| pkg-config version | `0.29.2-3` | `0.29.2-6` (+ matching SHA512) |
| libwinpthread | `git-9.0.0.6373...` | `13.0.0.r560.g3197fc7d6-1` (+ matching SHA512) |

After editing, re-run `vcpkg install` for the failed port (or the full dependency list).

**CI:** The same logic is applied by **`.github/scripts/patch-vcpkg-msys-pkgconfig.ps1`** on a fresh vcpkg checkout (or run that script once on a local tree).

---

## 2b. openal-soft on GitHub Actions (`windows-2022`)

The pinned port enables **WASAPI** on Windows and sets **`CMAKE_DISABLE_FIND_PACKAGE_WindowsSDK=ON`**, which often **fails CMake configure** on current runners (newer CMake / SDK layout).

**Fix:** Use the **WinMM** backend and disable WASAPI:

- **`vcpkg/ports/openal-soft/portfile.cmake`** in this repo is patched accordingly (local `vcpkg install`).

**CI:** **`.github/scripts/patch-vcpkg-openal-soft-winmm.ps1`** applies the same edit to a **fresh** vcpkg clone before `bootstrap-vcpkg.bat`.

Audio still works via the legacy WinMM path (typical for Win32 clients).

---

## 2c. GitHub Actions — vcpkg cache (`installed` + `downloads`)

Windows workflows clone a fresh vcpkg, then **`actions/cache@v4`** restores/saves the same paths **`lukka/run-vcpkg`** would use:

- **`${{ runner.workspace }}/vcpkg/installed`**
- **`${{ runner.workspace }}/vcpkg/downloads`**

Cache **key** includes a hash of **`.github/vcpkg-win-x86-static.cache-key`** and the **vcpkg patch scripts**. Edit the cache-key file (e.g. bump `PATCH_SET` or package list) when dependencies or patches change so runners don’t reuse stale binaries.

---

## 3. GitHub Actions (`windows-2022`, Windows-only)

- **Runner:** `windows-2019` → **`windows-2022`** (2019 image deprecated).
- **Jobs:** Android / macOS / Linux build jobs removed; only **Windows** (+ release steps that use Windows binaries).
- **vcpkg on CI:** Uses **vendored `vcpkg/`** from the repo (no separate clone of microsoft/vcpkg unless you change the workflow again).
- **MSBuild on CI:** **`/p:PlatformToolset=v143`** so the linker matches libraries built by **VS 2022**’s default toolchain when vcpkg runs on the runner.

Local **`vc16\otclient.vcxproj`** still targets **`v142`** by default; local builds can keep using VS 2019 toolset if installed, as long as vcpkg static libs were built with a compatible MSVC.

---

## 4. Documentation / repo layout

- **README / BUILD:** State that **vcpkg lives under `vcpkg\`** in the repo (same commit as upstream pin), not a separate download, and how to drop an old **submodule** if needed.
- **Submodule → plain folder:** Remove submodule metadata, delete **`vcpkg\.git`**, then add **`vcpkg/`** as normal files (large tree; **`installed/`**, **`buildtrees/`**, **`downloads/`** stay ignored via **`vcpkg/.gitignore`**).

---

## 5. Reference: Windows dependency one-liner (triplet `x86-windows-static`)

```text
boost-iostreams boost-asio boost-beast boost-system boost-variant boost-lockfree
boost-process boost-program-options boost-uuid boost-filesystem luajit glew
physfs openal-soft libogg libvorbis zlib libzip bzip2 openssl liblzma
```

(Each package suffix `:x86-windows-static` when using classic mode.)

---

## 6. Local build commands (after vcpkg install + integrate)

From **x86 Native Tools** (or MSBuild on PATH):

```bat
cd vc16
MSBuild otclient.sln /p:Configuration=DirectX /p:Platform=Win32 /m
MSBuild otclient.sln /p:Configuration=OpenGL /p:Platform=Win32 /m
```

Outputs: **`otclient_dx.exe`**, **`otclient_gl.exe`** at repo root.

---

*This file documents changes from bringing OTCv8 + pinned vcpkg to a working Windows build; it is not an official upstream OTCv8 document.*
