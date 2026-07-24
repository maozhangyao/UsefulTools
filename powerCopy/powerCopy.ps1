<#
.SYNOPSIS
    Recursively copy files from each subdirectory of Source to Destination.
.DESCRIPTION
    powerCopy processes every immediate subdirectory under Source, finds all
    files recursively within each, and copies them to Destination while
    preserving their relative path structure rooted at each subdirectory.

    Long paths (>260 characters) are handled via P/Invoke Win32 API (kernel32).
.PARAMETER Source
    Source directory. Its immediate subdirectories are processed.
    The Source directory itself is not copied.
.PARAMETER Destination
    Destination directory where files will be copied into.
    Created automatically if it does not exist.
.PARAMETER NoClobber
    If specified, existing files in Destination will NOT be overwritten.
    By default, files are overwritten silently.
.PARAMETER WhatIf
    Preview the operations without actually copying any files.
.EXAMPLE
    PS> .\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir
    Copy all files from each subdir of rootDir into destDir.
.EXAMPLE
    PS> .\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -NoClobber
    Copy but do NOT overwrite existing files.
.EXAMPLE
    PS> .\powerCopy.ps1 -Source D:\rootDir -Destination D:\destDir -WhatIf
    Preview only, no actual copy.
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Source,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Destination,

    [switch]$NoClobber,

    [switch]$WhatIf
)

# ---- Win32 P/Invoke for long-path support (>260 chars) ----
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateDirectoryW(string lpPathName, IntPtr lpSecurityAttributes);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CopyFileW(string lpExistingFileName, string lpNewFileName, bool bFailIfExists);
}
"@

function ConvertToExtendedPath {
    param([string]$Path)
    if ($Path -match '^\\\\\?\\') { return $Path }
    if ($Path -match '^\\\\') { return "\\?\UNC\$($Path.Substring(2))" }
    return "\\?\$Path"
}

function Ensure-Directory {
    param([string]$Path)
    if ($Path -eq '') { return }
    $parts = $Path.TrimEnd('\') -split '\\'
    $current = ''
    for ($i = 0; $i -lt $parts.Length; $i++) {
        if ($i -eq 0 -and $parts[$i] -match '^[A-Za-z]:$') {
            $current = $parts[$i]
            continue
        }
        $current = "$current\$($parts[$i])"
        $result = [Win32]::CreateDirectoryW((ConvertToExtendedPath $current), [IntPtr]::Zero)
        if (-not $result) {
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if ($err -ne 183) {
                throw "CreateDirectoryW failed (error $err) for: $current"
            }
        }
    }
}

# ---- Validate ----
$Source = $Source.TrimEnd('\')
$Destination = $Destination.TrimEnd('\')

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    Write-Error "Source directory not found: $Source"
    exit 1
}

# ---- Get immediate subdirectories under Source ----
$subDirs = Get-ChildItem -LiteralPath $Source -Directory -ErrorAction SilentlyContinue
if (-not $subDirs) {
    Write-Host "No subdirectories found under: $Source" -ForegroundColor Yellow
    exit 0
}

# ---- Ensure Destination exists ----
if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
    Write-Host "Creating destination: $Destination" -ForegroundColor Yellow
    Ensure-Directory $Destination
}

Write-Host "`n===== powerCopy =====" -ForegroundColor Cyan
Write-Host "  Source      : $Source" -ForegroundColor Cyan
Write-Host "  Destination : $Destination" -ForegroundColor Cyan
Write-Host "  NoClobber   : $($NoClobber.IsPresent)" -ForegroundColor Cyan
Write-Host "  Subdirs     : $($subDirs.Count)" -ForegroundColor Cyan
Write-Host ""

# ---- Process each subdirectory ----
$totalCopied = 0
$totalSkipped = 0
$totalErrors = 0

foreach ($subDir in $subDirs) {
    # Use extended path (.NET) for recursive file enumeration to handle >260 chars
    $rawPaths = try {
        [System.IO.Directory]::GetFiles(
            (ConvertToExtendedPath $subDir.FullName),
            '*',
            [System.IO.SearchOption]::AllDirectories
        )
    } catch {
        Write-Warning "  [SKIP] $($subDir.Name) : cannot enumerate files ($($_.Exception.Message))"
        $totalErrors++
        continue
    }
    if (-not $rawPaths) { continue }

    Write-Host "[$($subDir.Name)] scanning $($rawPaths.Count) files..." -ForegroundColor Green

    foreach ($extPath in $rawPaths) {
        # Strip \\?\ prefix from .NET-returned path
        $cleanPath = $extPath
        if ($cleanPath -match '^\\\\\?\\') {
            $cleanPath = $cleanPath.Substring(4)
        }

        $relativePath = $cleanPath.Substring($subDir.FullName.Length).TrimStart('\')
        $destPath = Join-Path -Path $Destination -ChildPath $relativePath
        $destParent = Split-Path -Path $destPath -Parent

        if ($WhatIf) {
            Write-Host "  [WhatIf] $relativePath" -ForegroundColor DarkYellow
            continue
        }

        try {
            # Check if destination file exists and NoClobber is set
            $fileExists = [System.IO.File]::Exists((ConvertToExtendedPath $destPath))
            if ($NoClobber -and $fileExists) {
                Write-Host "  [SKIP] $relativePath (already exists)" -ForegroundColor DarkGray
                $totalSkipped++
                continue
            }

            Ensure-Directory $destParent

            $srcExt = ConvertToExtendedPath $cleanPath
            $dstExt = ConvertToExtendedPath $destPath
            $copied = [Win32]::CopyFileW($srcExt, $dstExt, $false)
            if (-not $copied) {
                throw "CopyFileW failed (error $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
            }

            if ($fileExists) {
                Write-Host "  [OVR] $relativePath" -ForegroundColor Yellow
            } else {
                Write-Host "  [OK]  $relativePath" -ForegroundColor Green
            }
            $totalCopied++
        }
        catch {
            Write-Warning "  [FAIL] $relativePath : $_"
            $totalErrors++
        }
    }
}

# ---- Summary ----
if (-not $WhatIf) {
    Write-Host "`n===== Complete =====" -ForegroundColor Cyan
    Write-Host "  Copied  : $totalCopied" -ForegroundColor Green
    if ($NoClobber -and $totalSkipped -gt 0) {
        Write-Host "  Skipped : $totalSkipped" -ForegroundColor DarkGray
    }
    if ($totalErrors -gt 0) {
        Write-Host "  Errors  : $totalErrors" -ForegroundColor Red
    }
} else {
    Write-Host "`n[WhatIf] mode finished. No files were copied." -ForegroundColor DarkYellow
}
