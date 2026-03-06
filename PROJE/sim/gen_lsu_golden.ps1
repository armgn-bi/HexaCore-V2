# filepath: sim/gen_lsu_golden.ps1
# LSU golden log üreteci
# gen_golden.sv testbench'ini derler ve çalıştırır.
# Çıktı: tb/lsu.golden_clean.log.txt

$ErrorActionPreference = "Stop"
$env:PATH = "C:\Armagan\Vivado\Vivado\2024.1\bin;" + $env:PATH

$simDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $simDir

# Setup: copy mem files
Copy-Item -Force "..\tb\*.mem" "." -ErrorAction SilentlyContinue

Write-Host "==== Step 1: Compile Core RTL + gen_golden TB ===="
$out = & xvlog --sv --incr --relax -L work -f filelist_core.f "..\tb\gen_golden.sv" 2>&1 | Out-String
Write-Host $out
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: Compile failed"; exit 1 }

Write-Host "==== Step 2: Elaborate ===="
$out = & xelab --incr --relax --debug typical -L work gen_golden -s gen_golden_snap 2>&1 | Out-String
Write-Host $out
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: Elaborate failed"; exit 1 }

Write-Host "==== Step 3: Simulate ===="
$out = & xsim gen_golden_snap --runall --onerror quit 2>&1 | Out-String
Write-Host $out

# Copy generated golden log to tb/
if (Test-Path "lsu.golden_clean.log.txt") {
    Copy-Item -Force "lsu.golden_clean.log.txt" "..\tb\lsu.golden_clean.log.txt"
    Write-Host "==== SUCCESS: tb/lsu.golden_clean.log.txt generated ===="
    Write-Host "Lines: $((Get-Content '..\tb\lsu.golden_clean.log.txt').Count)"
} else {
    Write-Host "FAIL: lsu.golden_clean.log.txt not generated!"
    exit 1
}
