# run_dsp_perf_tests.ps1 — DSP Performans Karsilastirma Testi Runner
# 8 boyut x 2 test tipi = 16 test calistirir, sonuclari toplar
# Usage: powershell -ExecutionPolicy Bypass -File run_dsp_perf_tests.ps1

$ErrorActionPreference = "Stop"

# Vivado PATH ayari
if (-not (Get-Command "xvlog" -ErrorAction SilentlyContinue)) {
    $vivadoPaths = @(
        "C:\AMDDesignTools\2025.2\Vivado\bin",
        "C:\Xilinx\Vivado\2024.1\bin",
        "C:\Xilinx\Vivado\2023.2\bin"
    )
    foreach ($p in $vivadoPaths) {
        if (Test-Path $p) {
            $env:PATH = "$p;" + $env:PATH
            Write-Host "[INFO] Vivado PATH eklendi: $p"
            break
        }
    }
}

$simDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $simDir

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = "dsp_perf_report_$timestamp.log"
$summaryFile = "dsp_perf_summary_$timestamp.csv"

$header = @"
================================================================
  DSP PERFORMANS KARSILASTIRMA TESTI
  HexaCore-V2 SoC - CPU vs DSP FIR Filter
  Tarih: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
================================================================
"@
$header | Out-File $reportFile -Encoding utf8
$header | Write-Host

"TestType,SampleCount,Cycles,TestLabel,FirstOutput,LastOutput" | Out-File $summaryFile -Encoding utf8

Write-Host "[SETUP] Mem dosyalari kopyalaniyor..."
Copy-Item -Force "..\tb\*.mem" "." -ErrorAction SilentlyContinue
Copy-Item -Force "..\tb\*.txt" "." -ErrorAction SilentlyContinue

$sampleSizes = @(64, 128, 256, 512, 1024, 2048, 4096, 8192)
$testTypes = @("cpu", "dsp")

Write-Host ""
Write-Host "============================================================"
Write-Host "  ADIM 1: DERLEME (tek seferlik)"
Write-Host "============================================================"

Write-Host "[XVLOG] DSP Verilog derleniyor..."
$out = & xvlog --incr --relax -L work -f filelist_dsp_verilog.f 2>&1 | Out-String
$out | Out-File -Append $reportFile -Encoding utf8
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: DSP Verilog"; $out | Write-Host; exit 1 }
Write-Host "  [OK] DSP Verilog"

Write-Host "[XVLOG] Core + Bus + SoC derleniyor..."
$out = & xvlog --sv --incr --relax -L work -f filelist_core.f 2>&1 | Out-String
$out | Out-File -Append $reportFile -Encoding utf8
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: Core SV"; $out | Write-Host; exit 1 }
Write-Host "  [OK] Core + Bus + SoC"

Write-Host "[XVLOG] Performans Testbench derleniyor..."
$out = & xvlog --sv --incr --relax -L work -f filelist_tb_dsp_perf.f 2>&1 | Out-String
$out | Out-File -Append $reportFile -Encoding utf8
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: Testbench"; $out | Write-Host; exit 1 }
Write-Host "  [OK] Testbench"

Write-Host "[XELAB] Elaboration..."
$out = & xelab --incr --relax --debug typical -L work tb_dsp_perf -s tb_dsp_perf_snap 2>&1 | Out-String
$out | Out-File -Append $reportFile -Encoding utf8
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: Elaboration"; $out | Write-Host; exit 1 }
Write-Host "  [OK] Elaboration"

Write-Host ""
Write-Host "============================================================"
Write-Host "  ADIM 2: TEST CALISTIRMA (16 test)"
Write-Host "============================================================"

$results = @()
$testNum = 0
$totalTests = $sampleSizes.Count * $testTypes.Count

foreach ($N in $sampleSizes) {
    foreach ($type in $testTypes) {
        $testNum++
        $memFile = "imem_perf_${type}_${N}.mem"
        $testLabel = "${type}_${N}"
        $logFile = "logs\dsp_perf_${testLabel}.log"

        Write-Host ""
        Write-Host "----------------------------------------------------------------"
        Write-Host "  TEST $testNum/$totalTests : $testLabel (N=$N, Type=$type)"
        Write-Host "----------------------------------------------------------------"

        if (-not (Test-Path $memFile)) {
            Write-Host "  HATA: $memFile bulunamadi! Atlaniyor..."
            continue
        }
        Copy-Item -Force $memFile "imem_perf.mem"

        Write-Host "  [XSIM] Simulating $testLabel..."
        New-Item -ItemType Directory -Force -Path "logs" | Out-Null
        $out = & xsim tb_dsp_perf_snap --runall --onerror quit 2>&1 | Out-String
        $out | Out-File -Append $reportFile -Encoding utf8
        $out | Out-File $logFile -Encoding utf8

        $perfLine = ($out -split "`n") | Where-Object { $_ -match "PERF_RESULT," }
        if ($perfLine) {
            $firstPerf = if ($perfLine -is [array]) { $perfLine[0] } else { $perfLine }
            $firstPerf = $firstPerf.Trim()
            $firstPerf | Out-File -Append $summaryFile -Encoding utf8
            $parts = ($firstPerf -split ",")
            $typeStr = $parts[1]
            $cycles = $parts[3]

            Write-Host "  RESULT: Type=$typeStr N=$N Cycles=$cycles"
            $results += [PSCustomObject]@{
                TestType = $typeStr.Trim()
                N = [int]$N
                Cycles = [int]$cycles
                Label = $testLabel
            }
        } else {
            Write-Host "  WARNING: PERF_RESULT satiri bulunamadi!"
            ($out -split "`n") | Select-Object -Last 20 | ForEach-Object { Write-Host "    $_" }
            "NO_RESULT,$type,$N,0,$testLabel,0,0" | Out-File -Append $summaryFile -Encoding utf8
        }
    }
}

Write-Host ""
Write-Host ""
$sep = "=================================================================="
$reportLines = @()
$reportLines += ""
$reportLines += $sep
$reportLines += "  DSP PERFORMANS KARSILASTIRMA RAPORU"
$reportLines += "  HexaCore-V2 SoC - 11-TAP Hamming FIR Filter"
$reportLines += "  CPU (RV32I Software Multiply) vs DSP (Systolic Pipeline)"
$reportLines += $sep
$reportLines += ""
$reportLines += ("{0,-8} {1,12} {2,12} {3,10} {4,10}" -f "N", "CPU Cycle", "DSP Cycle", "Speedup", "Kazanc %")
$reportLines += ("{0,-8} {1,12} {2,12} {3,10} {4,10}" -f "--------", "------------", "------------", "----------", "--------")

foreach ($N in $sampleSizes) {
    $cpuResult = $results | Where-Object { $_.N -eq $N -and $_.TestType -eq "CPU" }
    $dspResult = $results | Where-Object { $_.N -eq $N -and $_.TestType -eq "DSP" }

    $cpuCycles = if ($cpuResult) { $cpuResult.Cycles } else { 0 }
    $dspCycles = if ($dspResult) { $dspResult.Cycles } else { 0 }

    if ($dspCycles -gt 0 -and $cpuCycles -gt 0) {
        $speedup = [math]::Round($cpuCycles / $dspCycles, 2)
        $gain = [math]::Round((1 - $dspCycles / $cpuCycles) * 100, 1)
    } else {
        $speedup = "N/A"
        $gain = "N/A"
    }

    $line = "{0,-8} {1,12} {2,12} {3,10} {4,10}" -f $N, $cpuCycles, $dspCycles, "${speedup}x", "${gain}%"
    $reportLines += $line
}

$reportLines += ""
$reportLines += $sep

foreach ($line in $reportLines) { Write-Host $line }
$reportLines | Out-File -Append $reportFile -Encoding utf8

Write-Host ""
Write-Host "  Detayli log: $reportFile"
Write-Host "  CSV ozet:    $summaryFile"
Write-Host ""
Write-Host "[TAMAMLANDI] Tum testler calistirildi."
