# openal-soft on windows-2022: WASAPI + CMAKE_DISABLE_FIND_PACKAGE_WindowsSDK breaks CMake configure.
# Use WinMM backend; disable WASAPI (sufficient for 32-bit OTC client).
param([Parameter(Mandatory)][string]$VcpkgRoot)
$path = Join-Path $VcpkgRoot "ports\openal-soft\portfile.cmake"
if (-not (Test-Path $path)) { throw "Not found: $path" }
$c = [System.IO.File]::ReadAllText($path)
if ($c -match 'DALSOFT_BACKEND_WASAPI=OFF') {
    Write-Host "openal-soft portfile already patched."
    exit 0
}
if ($c -notmatch 'DALSOFT_BACKEND_WINMM=OFF') {
    throw "openal-soft portfile: expected stock WinMM=OFF block."
}
$nl = if ($c -match "`r`n") { "`r`n" } else { "`n" }
$c = $c.Replace('-DALSOFT_BACKEND_WINMM=OFF', '-DALSOFT_BACKEND_WINMM=ON')
$c = $c.Replace(
    '-DALSOFT_REQUIRE_WASAPI=${ALSOFT_REQUIRE_WINDOWS}',
    "-DALSOFT_BACKEND_WASAPI=OFF${nl}        -DALSOFT_REQUIRE_WASAPI=OFF")
$c = $c.Replace("${nl}        -DCMAKE_DISABLE_FIND_PACKAGE_WindowsSDK=ON", '')
if ($c -notmatch 'MAYBE_UNUSED[\s\S]*ALSOFT_BACKEND_WASAPI') {
    $c = $c.Replace(
        "${nl}        ALSOFT_BACKEND_SOLARIS${nl}        ALSOFT_CONFIG",
        "${nl}        ALSOFT_BACKEND_SOLARIS${nl}        ALSOFT_BACKEND_WASAPI${nl}        ALSOFT_BACKEND_WINMM${nl}        ALSOFT_CONFIG")
}
[System.IO.File]::WriteAllText($path, $c)
Write-Host "Patched openal-soft portfile (WinMM, no WASAPI)."
