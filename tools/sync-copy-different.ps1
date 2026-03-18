<#
.SYNOPSIS
  Copy files from Source to Dest: skip when content is identical; copy when missing or different.

.PARAMETER Source
  Root directory to copy from.

.PARAMETER Dest
  Root directory to copy into (created if needed).

.PARAMETER Algorithm
  Hash algorithm (default SHA256). MD5 is faster on huge trees.

  Skips ".git" anywhere in the path.
  Under "vcpkg\", skips paths that vcpkg/.gitignore would ignore (downloads, buildtrees,
  packages, installed, *.exe, *.zip, most triplets except community + listed cmake files, etc.).
#>
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Dest,
    [ValidateSet('SHA256', 'MD5', 'SHA1')]
    [string]$Algorithm = 'SHA256'
)

function Test-IsVcpkgGitignored {
    param([string]$SubPath)
    # SubPath = path relative to vcpkg root (use \)
    $n = ($SubPath -replace '/', '\').TrimStart('\')
    if ($n -eq '') { return $false }

    if ($n -match '^\.vscode(\\|$)') { return $true }
    if ($n -match '^downloads(\\|$)') { return $true }
    if ($n -match '^packages(\\|$)') { return $true }
    if ($n -match '^buildtrees(\\|$)') { return $true }
    if ($n -match '^installed') { return $true }
    if ($n -match '^archives(\\|$)') { return $true }
    if ($n -match '^prefab(\\|$)') { return $true }
    if ($n -eq 'vcpkg.disable-metrics') { return $true }
    if ($n -match '^scripts\\buildsystems\\tmp(\\|$)') { return $true }

    $top = ($n -split '\\')[0]
    if ($top -match '^build' -and $top -ne 'buildsystems') { return $true }

    if ($n -match '\.(exe|zip)$') { return $true }
    if ($n -match '(^|\\)\.DS_Store$') { return $true }
    if ($n -match '\.swp$') { return $true }
    if ($n -match '^pythonenv3\.8(\\|$)') { return $true }
    if ($n -match '^\.venv(\\|$)') { return $true }
    if ($n -eq 'vcpkg-configuration.json') { return $true }

    if ($n -match '^triplets(\\|$)') {
        if ($n -match '^triplets\\community(\\|$)') { return $false }
        $allowedLeaf = @(
            'arm-uwp.cmake', 'arm64-windows.cmake', 'x64-linux.cmake', 'x64-osx.cmake',
            'x64-uwp.cmake', 'x64-windows-static.cmake', 'x64-windows.cmake', 'x86-windows.cmake'
        )
        if ($n -match '^triplets\\[^\\]+\.cmake$') {
            $leaf = Split-Path $n -Leaf
            if ($allowedLeaf -contains $leaf) { return $false }
        }
        return $true
    }

    return $false
}

$Source = $Source.TrimEnd('\', '/')
$Dest = $Dest.TrimEnd('\', '/')

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "Source not found or not a directory: $Source"
}

$new = 0
$updated = 0
$skipped = 0
$skippedVcpkgIgnore = 0

Get-ChildItem -LiteralPath $Source -Recurse -File -Force | ForEach-Object {
    $full = $_.FullName
    $rel = $full.Substring($Source.Length).TrimStart('\', '/')
    $segments = $rel -split '[\\/]'
    if ($segments -contains '.git') { return }

    if ($rel -match '^vcpkg[/\\](.+)$') {
        $sub = $Matches[1]
        if (Test-IsVcpkgGitignored $sub) {
            $script:skippedVcpkgIgnore++
            return
        }
    }

    $target = Join-Path $Dest $rel
    $targetDir = Split-Path -Parent $target

    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $full -Destination $target -Force
        $script:new++
        Write-Host "[new]     $rel"
        return
    }

    $hSrc = (Get-FileHash -LiteralPath $full -Algorithm $Algorithm).Hash
    $hDst = (Get-FileHash -LiteralPath $target -Algorithm $Algorithm).Hash
    if ($hSrc -eq $hDst) {
        $script:skipped++
        return
    }

    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $full -Destination $target -Force
    $script:updated++
    Write-Host "[updated] $rel"
}

Write-Host ""
Write-Host "Done. New: $new | Updated: $updated | Skipped (identical): $skipped | Skipped (vcpkg gitignore): $skippedVcpkgIgnore"
