# MSYS2 moved i686 packages from mingw/i686 to mingw/mingw32; old vcpkg URLs 404 on CI.
param([Parameter(Mandatory)][string]$VcpkgRoot)
$path = Join-Path $VcpkgRoot "scripts\cmake\vcpkg_find_acquire_program.cmake"
if (-not (Test-Path $path)) { throw "Not found: $path" }
$c = Get-Content $path -Raw
if ($c -notmatch 'mingw/i686/mingw-w64-i686-pkg-config') {
    if ($c -match 'mingw/mingw32/mingw-w64-i686-pkg-config') {
        Write-Host "vcpkg MSYS pkg-config paths already updated."
        exit 0
    }
    throw "vcpkg_find_acquire_program.cmake: expected PKGCONFIG MSYS block not found."
}
$c = $c.Replace('set(VERSION 0.29.2-3)', 'set(VERSION 0.29.2-6)')
$c = $c.Replace('set(program_version git-9.0.0.6373.5be8fcd83-1)', 'set(program_version 13.0.0.r560.g3197fc7d6-1)')
$c = $c.Replace(
    '"https://repo.msys2.org/mingw/i686/mingw-w64-i686-pkg-config-${VERSION}-any.pkg.tar.zst"',
    '"https://repo.msys2.org/mingw/mingw32/mingw-w64-i686-pkg-config-${VERSION}-any.pkg.tar.zst"')
$c = $c.Replace(
    '0c086bf306b6a18988cc982b3c3828c4d922a1b60fd24e17c3bead4e296ee6de48ce148bc6f9214af98be6a86cb39c37003d2dcb6561800fdf7d0d1028cf73a4',
    '4eb6388391311e2db541fb071de7d7840f63195d87a03a18e0b84d775f6366205c68f01f4c720722c4d5d618270883138bdbab236ce6794d294df338b17086d1')
$c = $c.Replace(
    '"https://repo.msys2.org/mingw/i686/mingw-w64-i686-libwinpthread-${program_version}-any.pkg.tar.zst"',
    '"https://repo.msys2.org/mingw/mingw32/mingw-w64-i686-libwinpthread-${program_version}-any.pkg.tar.zst"')
$c = $c.Replace(
    'c89c27b5afe4cf5fdaaa354544f070c45ace5e9d2f2ebb4b956a148f61681f050e67976894e6f52e42e708dadbf730fee176ac9add3c9864c21249034c342810',
    '03038bfe90ca06eae9d854f596d8ec289699779cca1be2aa0705c73a8e38a7ebd39353e7f79b743c688879209f07c582acfd1885efcd77a13ca2553f7192c35c')
[System.IO.File]::WriteAllText($path, $c)
