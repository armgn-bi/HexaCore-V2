# run_soc_sys_test.ps1 — Kapsamlı SoC Sistem Testi Runner
# Core → AXI → Tüm Periferaller (DMEM, UART, SPI, I2C, DSP)
# 22 doğrulama noktası + BFM'ler (UART loopback, SPI slave, I2C slave)
# Usage: powershell -ExecutionPolicy Bypass -File run_soc_sys_test.ps1

$ErrorActionPreference = "Stop"
$env:PATH = "C:\AMDDesignTools\2025.2\Vivado\bin;" + $env:PATH

$simDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $simDir

$logFile = "soc_sys_test.log"
"" | Out-File $logFile

function Log($msg) {
    Write-Host $msg
    $msg | Out-File -Append $logFile
}

# Setup: copy mem/txt files
Copy-Item -Force "..\tb\*.mem" "." -ErrorAction SilentlyContinue
Copy-Item -Force "..\tb\*.txt" "." -ErrorAction SilentlyContinue

# Step 1: Compile DSP Verilog
Log "==== Step 1: Compile DSP Verilog ===="
$out = & xvlog --incr --relax -L work -f filelist_dsp_verilog.f 2>&1 | Out-String
Log $out
if ($LASTEXITCODE -ne 0) { Log "FAIL: DSP Verilog compile failed"; exit 1 }

# Step 2: Compile Core + Bus + SoC (SystemVerilog)
Log "==== Step 2: Compile Core + Bus + SoC SV ===="
$out = & xvlog --sv --incr --relax -L work -f filelist_core.f 2>&1 | Out-String
Log $out
if ($LASTEXITCODE -ne 0) { Log "FAIL: Core SV compile failed"; exit 1 }

# Step 3: Compile System Test TB
Log "==== Step 3: Compile System Test TB ===="
$out = & xvlog --sv --incr --relax -L work -f filelist_tb_soc_sys.f 2>&1 | Out-String
Log $out
if ($LASTEXITCODE -ne 0) { Log "FAIL: System TB compile failed"; exit 1 }

# Step 4: Elaborate
Log "==== Step 4: Elaborate ===="
$out = & xelab --incr --relax --debug typical -L work tb_soc_system -s tb_soc_system_snap 2>&1 | Out-String
Log $out
if ($LASTEXITCODE -ne 0) { Log "FAIL: Elaboration failed"; exit 1 }

# Step 5: Simulate
Log "==== Step 5: Simulate ===="
$out = & xsim tb_soc_system_snap --runall --onerror quit 2>&1 | Out-String
Log $out

# Parse results
$passCount = ([regex]::Matches($out, 'PASS #')).Count
$failCount = ([regex]::Matches($out, 'FAIL #')).Count

Log ""
Log "==== SoC System Test Complete ===="
Log "Full log saved to: $logFile"

if ($failCount -gt 0) {
    Log "RESULT: $failCount FAIL(s) out of $($passCount + $failCount) tests"
    exit 1
} else {
    Log "RESULT: ALL $passCount tests PASSED"
    exit 0
}
