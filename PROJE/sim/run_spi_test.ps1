# run_spi_test.ps1 — SPI Periferal Fonksiyon Testi Runner
# Compile → Elaborate → Simulate
# Usage: powershell -ExecutionPolicy Bypass -File run_spi_test.ps1

$ErrorActionPreference = "Stop"
$env:PATH = "C:\AMDDesignTools\2025.2\Vivado\bin;" + $env:PATH

$simDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $simDir

$logFile = "spi_test.log"
"" | Out-File $logFile

function Log($msg) {
    Write-Host $msg
    $msg | Out-File -Append $logFile
}

# Step 1: Compile SPI RTL (SystemVerilog)
Log "==== Step 1: Compile SPI RTL ===="
$out = & xvlog --sv --incr --relax -L work -f filelist_spi_rtl.f 2>&1 | Out-String
Log $out
if ($LASTEXITCODE -ne 0) { Log "FAIL: SPI RTL compile failed"; exit 1 }

# Step 2: Compile SPI TB
Log "==== Step 2: Compile SPI Testbench ===="
$out = & xvlog --sv --incr --relax -L work -f filelist_tb_spi.f 2>&1 | Out-String
Log $out
if ($LASTEXITCODE -ne 0) { Log "FAIL: SPI TB compile failed"; exit 1 }

# Step 3: Elaborate
Log "==== Step 3: Elaborate ===="
$out = & xelab --incr --relax --debug typical -L work tb_spi -s tb_spi_snap 2>&1 | Out-String
Log $out
if ($LASTEXITCODE -ne 0) { Log "FAIL: Elaboration failed"; exit 1 }

# Step 4: Simulate
Log "==== Step 4: Simulate ===="
$out = & xsim tb_spi_snap --runall --onerror quit 2>&1 | Out-String
Log $out

# Parse results
$passCount = ([regex]::Matches($out, 'PASS #')).Count
$failCount = ([regex]::Matches($out, 'FAIL #')).Count

Log ""
Log "==== SPI Fonksiyon Testi Complete ===="
Log "Full log saved to: $logFile"

if ($failCount -gt 0) {
    Log "RESULT: $failCount FAIL(s) detected out of $($passCount + $failCount) tests"
    exit 1
} else {
    Log "RESULT: ALL $passCount tests PASSED"
    exit 0
}
