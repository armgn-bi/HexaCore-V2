<#
.SYNOPSIS
    DQN Performans Testi - CPU-only vs DQN+CPU Paralel karsilastirma.

.DESCRIPTION
    Bu script sim/ dizininde calistirilmalidir.
    Vivado bin dizini PATH'te olmalidir.

.EXAMPLE
    .\run_dqn_perf.ps1

.NOTES
    Vivado PATH'e eklemek icin:
    $env:PATH = "C:\Xilinx\2025.1\Vivado\bin;" + $env:PATH
#>

# Konfigrasyon
$XVLOG = "xvlog"
$XELAB = "xelab"
$XSIM  = "xsim"

$TB_TOP   = "tb_dqn_perf"
$SNAPSHOT = "${TB_TOP}_snap"
$FLIST    = "filelist_dqn_perf.f"
$LOG_DIR  = "logs"

$XVLOG_FLAGS = "--sv --incr --relax -L work"
$XELAB_FLAGS = "--incr --relax --debug typical -L work"
$XSIM_FLAGS  = "--runall --onerror quit"

# Log dizini
if (!(Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR | Out-Null }

$separator = "=" * 64

Write-Host ""
Write-Host $separator -ForegroundColor Cyan
Write-Host "  DQN Performans Testi - CPU-only vs DQN+CPU Paralel"
Write-Host $separator -ForegroundColor Cyan

# Derleme
Write-Host ""
Write-Host "[XVLOG] DQN Performans Testi kaynaklari derleniyor..." -ForegroundColor Yellow
$compileCmd = "$XVLOG $XVLOG_FLAGS -f $FLIST"
Invoke-Expression $compileCmd 2>&1 | Tee-Object -FilePath "$LOG_DIR/dqn_perf_xvlog.log"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[HATA] Derleme basarisiz!" -ForegroundColor Red
    exit 1
}

# Elaboration
Write-Host ""
Write-Host "[XELAB] Elaboration: $TB_TOP -> $SNAPSHOT" -ForegroundColor Yellow
$elabCmd = "$XELAB $XELAB_FLAGS $TB_TOP -s $SNAPSHOT"
Invoke-Expression $elabCmd 2>&1 | Tee-Object -FilePath "$LOG_DIR/dqn_perf_xelab.log"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[HATA] Elaboration basarisiz!" -ForegroundColor Red
    exit 1
}

# Simulasyon
Write-Host ""
Write-Host "[XSIM] Simulasyon baslatiliyor: $SNAPSHOT" -ForegroundColor Yellow
$simCmd = "$XSIM $SNAPSHOT $XSIM_FLAGS"
Invoke-Expression $simCmd 2>&1 | Tee-Object -FilePath "$LOG_DIR/dqn_perf_xsim.log"

Write-Host ""
Write-Host $separator -ForegroundColor Cyan
Write-Host "  DQN Performans Testi tamamlandi."
Write-Host "  Log dosyasi: $LOG_DIR/dqn_perf_xsim.log"
Write-Host $separator -ForegroundColor Cyan
