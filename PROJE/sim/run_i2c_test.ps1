# run_i2c_test.ps1 — I2C Periferal Fonksiyon Testi Runner
# Compile → Elaborate → Simulate
# Usage: powershell -ExecutionPolicy Bypass -File run_i2c_test.ps1

$ErrorActionPreference = "Stop"
$env:PATH = "C:\AMDDesignTools\2025.2\Vivado\bin;" + $env:PATH

$simDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $simDir

$logFile = "i2c_test.log"
"" | Out-File $logFile

function Log($msg) {
    Write-Host $msg
    $msg | Out-File -Append $logFile
}

# Step 1: Compile I2C RTL (SystemVerilog)
Log "==== Step 1: Compile I2C RTL ===="
$out = & xvlog --sv --incr --relax -L work -f filelist_i2c_rtl.f 2>&1 | Out-String
Log $out
if ($LASTEXITCODE -ne 0) { Log "FAIL: I2C RTL compile failed"; exit 1 }

# Step 2: Compile I2C TB
Log "==== Step 2: Compile I2C Testbench ===="
$out = & xvlog --sv --incr --relax -L work -f filelist_tb_i2c.f 2>&1 | Out-String
Log $out
if ($LASTEXITCODE -ne 0) { Log "FAIL: I2C TB compile failed"; exit 1 }

# Step 3: Elaborate
Log "==== Step 3: Elaborate ===="
$out = & xelab --incr --relax --debug typical -L work tb_i2c -s tb_i2c_snap 2>&1 | Out-String
Log $out
if ($LASTEXITCODE -ne 0) { Log "FAIL: Elaboration failed"; exit 1 }

# Step 4: Simulate
Log "==== Step 4: Simulate ===="
$out = & xsim tb_i2c_snap --runall --onerror quit 2>&1 | Out-String
Log $out

# Parse results
$passCount = ([regex]::Matches($out, 'PASS #')).Count
$failCount = ([regex]::Matches($out, 'FAIL #')).Count

Log ""
Log "==== I2C Fonksiyon Testi Complete ===="
Log "Full log saved to: $logFile"

if ($failCount -gt 0) {
    Log "RESULT: $failCount FAIL(s) detected out of $($passCount + $failCount) tests"
    exit 1
} else {
    Log "RESULT: ALL $passCount tests PASSED"
    exit 0
}
