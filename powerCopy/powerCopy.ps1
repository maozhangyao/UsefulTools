<#
.SYNOPSIS
    Copy files from Source to Destination with two configurable modes and long-path support.
.DESCRIPTION
    Mode A (default)  : Source folder itself is the root — all its content is copied.
    Mode B (-FromSubDirs): Each immediate subfolder under Source is a root — content
                          from each subfolder is copied separately.

    Supports -NoRecurse (flat), -NoClobber (no overwrite), and -WhatIf (preview).
    Long paths (>260 chars) are handled via Win32 API + \\?\ prefix.
.PARAMETER Source
    Source folder path (position 0). Supports absolute, relative, UNC paths.
.PARAMETER Destination
    Destination folder path (position 1). Created automatically if missing.
.PARAMETER FromSubDirs
    Switch: process each immediate subfolder under Source as a separate root (Mode B).
    Default: Source itself is the root (Mode A).
.PARAMETER NoRecurse
    Switch: do not recurse into subfolders — only root-level files are processed.
.PARAMETER NoClobber
    Switch: skip existing destination files instead of overwriting.
.PARAMETER WhatIf
    Switch: preview mode — list files without copying.
.EXAMPLE
    PS> .\powerCopy.ps1 D:\rootDir D:\destDir
    Mode A: copy everything under rootDir into destDir.
.EXAMPLE
    PS> .\powerCopy.ps1 D:\rootDir D:\destDir -FromSubDirs
    Mode B: copy content from each subfolder of rootDir into destDir.
.EXAMPLE
    PS> .\powerCopy.ps1 D:\rootDir D:\destDir -FromSubDirs -NoRecurse -NoClobber -WhatIf
    Preview Mode B flat copy without overwriting.
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Source,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Destination,

    [switch]$FromSubDirs,
    [switch]$NoRecurse,
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

function Get-Files {
    param([string]$RootPath, [bool]$Recurse)
    $searchOption = if ($Recurse) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
    $extPaths = try {
        [System.IO.Directory]::GetFiles((ConvertToExtendedPath $RootPath), '*', $searchOption)
    } catch {
        throw $_
    }
    return $extPaths
}

function Write-Config {
    Write-Host "`n===== powerCopy =====" -ForegroundColor Cyan
    Write-Host "  Source      : $Source" -ForegroundColor Cyan
    Write-Host "  Destination : $Destination" -ForegroundColor Cyan
    Write-Host "  FromSubDirs : $($FromSubDirs.IsPresent)" -ForegroundColor Cyan
    Write-Host "  NoRecurse   : $($NoRecurse.IsPresent)" -ForegroundColor Cyan
    Write-Host "  NoClobber   : $($NoClobber.IsPresent)" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Summary {
    param([int]$Copied, [int]$Skipped, [int]$Errors)
    Write-Host "`n===== Complete =====" -ForegroundColor Cyan
    Write-Host "  Copied  : $Copied" -ForegroundColor Green
    Write-Host "  Skipped : $Skipped" -ForegroundColor DarkGray
    Write-Host "  Errors  : $Errors" -ForegroundColor Red
}

# Ensure paths are absolute for consistent handling
$Source = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    Write-Error "Source directory not found: $Source"
    exit 1
}

# Create destination if needed
if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
    if (-not $WhatIf) {
        Ensure-Directory $Destination
    }
}

Write-Config

$totalCopied = 0
$totalSkipped = 0
$totalErrors = 0

# ---- Determine processing roots ----
$roots = @()
if ($FromSubDirs) {
    # Mode B: each immediate subfolder is a root
    $subDirs = Get-ChildItem -LiteralPath $Source -Directory -ErrorAction SilentlyContinue
    foreach ($d in $subDirs) { $roots += @{ Path = $d.FullName; Label = $d.Name } }
    if ($roots.Count -eq 0) {
        Write-Host "No subdirectories found under: $Source" -ForegroundColor Yellow
        exit 0
    }
} else {
    # Mode A: Source itself is the root
    $roots += @{ Path = $Source; Label = $null }
}

# ---- Process each root ----
foreach ($root in $roots) {
    if ($FromSubDirs -and $root.Label) {
        Write-Host "--- [$($root.Label)] ---" -ForegroundColor Green
    }

    $rawPaths = try {
        Get-Files -RootPath $root.Path -Recurse (-not $NoRecurse)
    } catch {
        if ($FromSubDirs) {
            Write-Host "  [SKIP] $($root.Label) : cannot enumerate files ($($_.Exception.Message))" -ForegroundColor DarkGray
        } else {
            Write-Host "  [SKIP] cannot enumerate files ($($_.Exception.Message))" -ForegroundColor DarkGray
        }
        $totalErrors++
        continue
    }

    if (-not $rawPaths) { continue }

    foreach ($extPath in $rawPaths) {
        $cleanPath = $extPath
        if ($cleanPath -match '^\\\\\?\\') {
            $cleanPath = $cleanPath.Substring(4)
        }

        $relativePath = $cleanPath.Substring($root.Path.Length).TrimStart('\')
        $destPath = Join-Path -Path $Destination -ChildPath $relativePath
        $destParent = Split-Path -Path $destPath -Parent

        if ($WhatIf) {
            if ($FromSubDirs) {
                Write-Host "  [WhatIf] $relativePath" -ForegroundColor DarkYellow
            } else {
                Write-Host "  [WhatIf] $relativePath" -ForegroundColor DarkYellow
            }
            continue
        }

        try {
            $fileExists = [System.IO.File]::Exists((ConvertToExtendedPath $destPath))
            if ($NoClobber -and $fileExists) {
                Write-Host "  [SKIP] $relativePath" -ForegroundColor DarkGray
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
                Write-Host "  [OVR]  $relativePath" -ForegroundColor Yellow
            } else {
                Write-Host "  [OK]   $relativePath" -ForegroundColor Green
            }
            $totalCopied++
        } catch {
            Write-Host "  [FAIL] $relativePath : $_" -ForegroundColor Red
            $totalErrors++
        }
    }
}

Write-Summary -Copied $totalCopied -Skipped $totalSkipped -Errors $totalErrors
if ($WhatIf) {
    Write-Host "`n[WhatIf] mode finished. No files were copied." -ForegroundColor DarkYellow
}
