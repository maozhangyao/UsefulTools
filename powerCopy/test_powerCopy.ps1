#Requires -Version 5.1
$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "powerCopy.ps1"
$testRoot = Join-Path -Path $env:TEMP -ChildPath "powerCopyTest_$(Get-Random)"
$testSrc = Join-Path -Path $testRoot -ChildPath "source"
$testDst = Join-Path -Path $testRoot -ChildPath "dest"
$passed = 0
$failed = 0

function Init-Test {
    if (Test-Path -LiteralPath $testRoot) {
        # Use extended-length path to handle long paths during cleanup
        $extRoot = "\\?\$testRoot"
        if (Test-Path -LiteralPath $extRoot) {
            Remove-Item -LiteralPath $extRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $testSrc -Force | Out-Null
}

function Assert-True {
    param([string]$Desc, [scriptblock]$Block)
    $global:passed++
    try {
        $result = & $Block
        if (-not $result) { throw "assertion failed" }
        Write-Host "  [PASS] $Desc" -ForegroundColor Green
    } catch {
        $global:passed--
        $global:failed++
        Write-Host "  [FAIL] $Desc : $_" -ForegroundColor Red
    }
}

# ============================================================
Write-Host "`n========== powerCopy Test Suite ==========" -ForegroundColor Cyan
Write-Host "Started: $(Get-Date)`n" -ForegroundColor Cyan

# Test 1: Mode A basic recursive copy
Write-Host "--- Test 1: Mode A (default) recursive copy ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType File -Path "$testSrc\fileA.txt" -Force | Out-Null
New-Item -ItemType Directory -Path "$testSrc\sub1" -Force | Out-Null
New-Item -ItemType File -Path "$testSrc\sub1\fileB.txt" -Force | Out-Null
& $scriptPath -Source $testSrc -Destination $testDst | Out-Null
Assert-True "Mode A: root file copied" { (Test-Path -LiteralPath "$testDst\fileA.txt") }
Assert-True "Mode A: subdir file copied" { (Test-Path -LiteralPath "$testDst\sub1\fileB.txt") }

# Test 2: Mode B -FromSubDirs
Write-Host "--- Test 2: Mode B (-FromSubDirs) ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType Directory -Path "$testSrc\dir001" -Force | Out-Null
New-Item -ItemType File -Path "$testSrc\dir001\file1.txt" -Force | Out-Null
New-Item -ItemType Directory -Path "$testSrc\dir001\sub" -Force | Out-Null
New-Item -ItemType File -Path "$testSrc\dir001\sub\file2.txt" -Force | Out-Null
New-Item -ItemType Directory -Path "$testSrc\dir002" -Force | Out-Null
New-Item -ItemType File -Path "$testSrc\dir002\data.log" -Force | Out-Null
& $scriptPath -Source $testSrc -Destination $testDst -FromSubDirs | Out-Null
Assert-True "Mode B: dir001/file1.txt -> dest/file1.txt" { (Test-Path -LiteralPath "$testDst\file1.txt") }
Assert-True "Mode B: dir001/sub/file2.txt -> dest/sub/file2.txt" { (Test-Path -LiteralPath "$testDst\sub\file2.txt") }
Assert-True "Mode B: dir002/data.log -> dest/data.log" { (Test-Path -LiteralPath "$testDst\data.log") }

# Test 3: Mode A -NoRecurse
Write-Host "--- Test 3: Mode A + NoRecurse ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType File -Path "$testSrc\root.txt" -Force | Out-Null
New-Item -ItemType Directory -Path "$testSrc\sub" -Force | Out-Null
New-Item -ItemType File -Path "$testSrc\sub\nested.txt" -Force | Out-Null
& $scriptPath -Source $testSrc -Destination $testDst -NoRecurse | Out-Null
Assert-True "NoRecurse: root file copied" { (Test-Path -LiteralPath "$testDst\root.txt") }
Assert-True "NoRecurse: nested file NOT copied" { (-not (Test-Path -LiteralPath "$testDst\sub\nested.txt")) }

# Test 4: Mode B + NoRecurse
Write-Host "--- Test 4: Mode B + NoRecurse ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType Directory -Path "$testSrc\dirA" -Force | Out-Null
New-Item -ItemType File -Path "$testSrc\dirA\a.txt" -Force | Out-Null
New-Item -ItemType Directory -Path "$testSrc\dirA\sub" -Force | Out-Null
New-Item -ItemType File -Path "$testSrc\dirA\sub\b.txt" -Force | Out-Null
& $scriptPath -Source $testSrc -Destination $testDst -FromSubDirs -NoRecurse | Out-Null
Assert-True "Mode B+NoRecurse: root file copied" { (Test-Path -LiteralPath "$testDst\a.txt") }
Assert-True "Mode B+NoRecurse: nested NOT copied" { (-not (Test-Path -LiteralPath "$testDst\sub\b.txt")) }

# Test 5: -NoClobber (no overwrite)
Write-Host "--- Test 5: NoClobber ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType File -Path "$testSrc\keep.txt" -Force | Out-Null
New-Item -ItemType Directory -Path $testDst -Force | Out-Null
[System.IO.File]::WriteAllText("$testDst\keep.txt", "original")
& $scriptPath -Source $testSrc -Destination $testDst -NoClobber | Out-Null
Assert-True "NoClobber: dest file still exists" { (Test-Path -LiteralPath "$testDst\keep.txt") }
Assert-True "NoClobber: file NOT overwritten" { ([System.IO.File]::ReadAllText("$testDst\keep.txt")) -eq "original" }

# Test 6: Default overwrite
Write-Host "--- Test 6: Default overwrite ---" -ForegroundColor Yellow
Init-Test
[System.IO.File]::WriteAllText("$testSrc\overwrite.txt", "new")
New-Item -ItemType Directory -Path $testDst -Force | Out-Null
[System.IO.File]::WriteAllText("$testDst\overwrite.txt", "old")
& $scriptPath -Source $testSrc -Destination $testDst | Out-Null
Assert-True "Default overwrite: dest file exists" { (Test-Path -LiteralPath "$testDst\overwrite.txt") }
Assert-True "Default overwrite: file overwritten with new content" { ([System.IO.File]::ReadAllText("$testDst\overwrite.txt")) -eq "new" }

# Test 7: -WhatIf preview mode
Write-Host "--- Test 7: WhatIf preview mode ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType File -Path "$testSrc\preview.txt" -Force | Out-Null
& $scriptPath -Source $testSrc -Destination $testDst -WhatIf | Out-Null
Assert-True "WhatIf: file NOT copied" { (-not (Test-Path -LiteralPath "$testDst\preview.txt")) }

# Test 8: Source folder does not exist
Write-Host "--- Test 8: Source folder missing ---" -ForegroundColor Yellow
Init-Test
& $scriptPath -Source "Z:\nonexistent_path_12345" -Destination $testDst -ErrorAction SilentlyContinue 2>&1 | Out-Null
Assert-True "Missing source: exit code not zero" { ($LASTEXITCODE -ne 0) }

# Test 9: Mode B with no subdirs
Write-Host "--- Test 9: Mode B no subdirs ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType File -Path "$testSrc\root.txt" -Force | Out-Null
& $scriptPath -Source $testSrc -Destination $testDst -FromSubDirs 2>&1 | Out-Null
Assert-True "No subdirs: dest folder exists (script creates it early)" { (Test-Path -LiteralPath $testDst -PathType Container) }

# Test 10: Long path support (>260 chars)
Write-Host "--- Test 10: Long path (>260 chars) ---" -ForegroundColor Yellow
Init-Test
$longDir = $testSrc
1..15 | ForEach-Object { $longDir = Join-Path -Path $longDir -ChildPath ("subfolder_$_" + "x" * 10) }
$longFile = Join-Path -Path $longDir -ChildPath ("longfile_" + "y" * 50 + ".txt")
# Use extended-length path prefix to create the long directory and file
$extDir = "\\?\$longDir"
$extFile = "\\?\$longFile"
[System.IO.Directory]::CreateDirectory($extDir) | Out-Null
[System.IO.File]::WriteAllText($extFile, "long path test content")
Assert-True "Long path: file path >260 chars" { ($longFile.Length -gt 260) }
$targetLongDir = Join-Path -Path $testDst -ChildPath ($longDir.Substring($testSrc.Length + 1))
$targetLongFile = Join-Path -Path $targetLongDir -ChildPath ("longfile_" + "y" * 50 + ".txt")
& $scriptPath -Source $testSrc -Destination $testDst | Out-Null
# Use extended-length path for verification too
$extTarget = "\\?\$targetLongFile"
Assert-True "Long path: file copied successfully" { ([System.IO.File]::Exists($extTarget)) }
Assert-True "Long path: content correct" { ([System.IO.File]::ReadAllText($extTarget)) -eq "long path test content" }

# Test 11: Destination auto-created
Write-Host "--- Test 11: Destination auto-created ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType File -Path "$testSrc\auto.txt" -Force | Out-Null
& $scriptPath -Source $testSrc -Destination $testDst | Out-Null
Assert-True "Auto-create: dest folder exists" { (Test-Path -LiteralPath $testDst -PathType Container) }

# Test 12: Relative path support
Write-Host "--- Test 12: Relative path support ---" -ForegroundColor Yellow
Init-Test
Push-Location -LiteralPath $testRoot
New-Item -ItemType Directory -Path "source\rel" -Force | Out-Null
New-Item -ItemType File -Path "source\rel\data.txt" -Force | Out-Null
& $scriptPath -Source "source" -Destination "dest_rel" 2>&1 | Out-Null
Assert-True "Relative: file copied" { (Test-Path -LiteralPath "$testRoot\dest_rel\rel\data.txt") }
Pop-Location

# Test 13: Path separator compat (/ vs \)
Write-Host "--- Test 13: Path separator compatibility ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType File -Path "$testSrc\sep.txt" -Force | Out-Null
$srcNorm = $testSrc -replace '\\', '/'
& $scriptPath -Source $srcNorm -Destination $testDst | Out-Null
Assert-True "Separator compat: file copied" { (Test-Path -LiteralPath "$testDst\sep.txt") }

# Test 14: WhatIf mode (Mode A)
Write-Host "--- Test 14: WhatIf mode (Mode A) ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType File -Path "$testSrc\w1.txt" -Force | Out-Null
New-Item -ItemType File -Path "$testSrc\w2.txt" -Force | Out-Null
& $scriptPath -Source $testSrc -Destination $testDst -WhatIf | Out-Null
Assert-True "WhatIf ModeA: dest folder NOT created" { (-not (Test-Path -LiteralPath $testDst -PathType Container)) }

# Test 15: Mode B WhatIf
Write-Host "--- Test 15: Mode B + WhatIf ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType Directory -Path "$testSrc\grp1" -Force | Out-Null
New-Item -ItemType File -Path "$testSrc\grp1\g1.txt" -Force | Out-Null
New-Item -ItemType Directory -Path "$testSrc\grp2" -Force | Out-Null
New-Item -ItemType File -Path "$testSrc\grp2\g2.txt" -Force | Out-Null
& $scriptPath -Source $testSrc -Destination $testDst -FromSubDirs -WhatIf 2>&1 | Out-Null
Assert-True "Mode B WhatIf: dest folder NOT created" { (-not (Test-Path -LiteralPath $testDst -PathType Container)) }

# Test 16: Positional parameters
Write-Host "--- Test 16: Positional parameters ---" -ForegroundColor Yellow
Init-Test
New-Item -ItemType File -Path "$testSrc\pos.txt" -Force | Out-Null
& $scriptPath $testSrc $testDst | Out-Null
Assert-True "Positional: file copied" { (Test-Path -LiteralPath "$testDst\pos.txt") }

# Cleanup (use extended-length path to handle long paths)
Remove-Item -LiteralPath "\\?\$testRoot" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host "`n========== Test Results ==========" -ForegroundColor Cyan
Write-Host "  Passed: $passed" -ForegroundColor Green
Write-Host "  Failed: $failed" -ForegroundColor Red
Write-Host "Finished: $(Get-Date)" -ForegroundColor Cyan
if ($failed -gt 0) { exit 1 } else { exit 0 }
