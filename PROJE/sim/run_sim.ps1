<#
.SYNOPSIS
    Vivado XSIM ile RISC-V SoC simülasyon scripti.

.DESCRIPTION
    Bu script sim/ dizininde çalıştırılmalıdır.
    Vivado'nun bin dizini PATH'te olmalıdır.

.PARAMETER Target
    Çalıştırılacak hedef: compile, elaborate, sim, all, wave, clean
    Varsayılan: all

.EXAMPLE
    .\run_sim.ps1                 # compile + elaborate + sim
    .\run_sim.ps1 -Target compile # Sadece derleme
    .\run_sim.ps1 -Target clean   # Temizleme
    .\run_sim.ps1 -Target wave    # GUI waveform

.NOTES
    Vivado'yu PATH'e eklemek için:
    $env:PATH = "C:\Xilinx\Vivado\2024.1\bin;" + $env:PATH
#>

param(
    [ValidateSet("all", "compile", "elaborate", "sim", "wave", "sim_vcd", "clean", "check", "soc_test", "help")]
    [string]$Target = "all"
)

# ═══════════════════════════════════════════════════════════════
# Konfigürasyon
# ═══════════════════════════════════════════════════════════════
$TB_TOP      = "tb_rv_all"
$SNAPSHOT    = "${TB_TOP}_snap"
$LOG_DIR     = "logs"
$TB_DATA_DIR = "..\tb"

$FLIST_CORE  = "filelist_core.f"
$FLIST_DSP_V = "filelist_dsp_verilog.f"
$FLIST_TB    = "filelist_tb.f"

$XVLOG_FLAGS_SV = "--sv --incr --relax -L work"
$XVLOG_FLAGS_V  = "--incr --relax -L work"
$XELAB_FLAGS    = "--incr --relax --debug typical -L work"
$XSIM_FLAGS     = "--runall --onerror quit"

# ═══════════════════════════════════════════════════════════════
# Yardımcı Fonksiyonlar
# ═══════════════════════════════════════════════════════════════

function Write-Banner([string]$msg) {
    Write-Host ""
    Write-Host ("=" * 56) -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host ("=" * 56) -ForegroundColor Cyan
}

function Test-VivadoInPath {
    $xvlog = Get-Command xvlog -ErrorAction SilentlyContinue
    if (-not $xvlog) {
        Write-Host "[HATA] 'xvlog' PATH'te bulunamadi!" -ForegroundColor Red
        Write-Host "       Vivado bin dizinini PATH'e ekleyin:" -ForegroundColor Yellow
        Write-Host '       $env:PATH = "C:\Xilinx\Vivado\2024.1\bin;" + $env:PATH' -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[INFO] Vivado bulundu: $($xvlog.Source)" -ForegroundColor Green
}

function Setup-Links {
    Write-Host "[SETUP] tb/ dizinindeki mem/log dosyalari kopyalaniyor..." -ForegroundColor Yellow
    if (Test-Path $TB_DATA_DIR) {
        Get-ChildItem "$TB_DATA_DIR\*.mem" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName -Destination . -Force
        }
        Get-ChildItem "$TB_DATA_DIR\*.txt" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName -Destination . -Force
        }
        Get-ChildItem "$TB_DATA_DIR\*.log.txt" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName -Destination . -Force
        }
    }
}

# ═══════════════════════════════════════════════════════════════
# Hedef Fonksiyonlar
# ═══════════════════════════════════════════════════════════════

function Invoke-Compile {
    Test-VivadoInPath
    Setup-Links
    if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR | Out-Null }

    Write-Banner "XVLOG: DSP Verilog dosyalari derleniyor"
    $cmd = "xvlog $XVLOG_FLAGS_V -f $FLIST_DSP_V"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\xvlog_dsp.log"
    if ($LASTEXITCODE -ne 0) { Write-Host "[HATA] DSP Verilog derleme basarisiz!" -ForegroundColor Red; exit 1 }

    Write-Banner "XVLOG: Core + Bus + SoC (SystemVerilog) derleniyor"
    $cmd = "xvlog $XVLOG_FLAGS_SV -f $FLIST_CORE"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\xvlog_core.log"
    if ($LASTEXITCODE -ne 0) { Write-Host "[HATA] Core derleme basarisiz!" -ForegroundColor Red; exit 1 }

    Write-Banner "XVLOG: Testbench derleniyor"
    $cmd = "xvlog $XVLOG_FLAGS_SV -f $FLIST_TB"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\xvlog_tb.log"
    if ($LASTEXITCODE -ne 0) { Write-Host "[HATA] TB derleme basarisiz!" -ForegroundColor Red; exit 1 }

    Write-Host "`n[XVLOG] Derleme tamamlandi." -ForegroundColor Green
}

function Invoke-Elaborate {
    Test-VivadoInPath
    if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR | Out-Null }

    Write-Banner "XELAB: Elaboration — $TB_TOP -> $SNAPSHOT"
    $cmd = "xelab $XELAB_FLAGS $TB_TOP -s $SNAPSHOT"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\xelab.log"
    if ($LASTEXITCODE -ne 0) { Write-Host "[HATA] Elaboration basarisiz!" -ForegroundColor Red; exit 1 }

    Write-Host "`n[XELAB] Elaboration tamamlandi." -ForegroundColor Green
}

function Invoke-Sim {
    Test-VivadoInPath
    if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR | Out-Null }

    Write-Banner "XSIM: Simulasyon baslatiliyor — $SNAPSHOT"
    $cmd = "xsim $SNAPSHOT $XSIM_FLAGS"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\xsim.log"

    Write-Host "`n[XSIM] Simulasyon tamamlandi." -ForegroundColor Green
}

function Invoke-Wave {
    Test-VivadoInPath
    Write-Banner "XSIM: Waveform GUI aciliyor"
    Start-Process xsim -ArgumentList "$SNAPSHOT --gui"
}

function Invoke-Check {
    Write-Banner "CHECK: Derleme + Elaboration kontrolu"
    Invoke-Compile
    Invoke-Elaborate
    Write-Host ""
    Write-Host ("=" * 56) -ForegroundColor Green
    Write-Host "  [CHECK] Derleme + Elaboration basarili!" -ForegroundColor Green
    Write-Host "  RTL syntax/elaboration hatalari yok." -ForegroundColor Green
    Write-Host ("=" * 56) -ForegroundColor Green
}

function Invoke-SimVcd {
    Test-VivadoInPath
    if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR | Out-Null }

    Write-Banner "XSIM: VCD kaydıyla simulasyon"
    $cmd = "xsim $SNAPSHOT --tclbatch xsim_run.tcl"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\xsim_vcd.log"

    Write-Host "`n[XSIM] VCD simulasyon tamamlandi." -ForegroundColor Green
}

function Invoke-Clean {
    Write-Banner "Temizleniyor"
    $dirsToRemove = @("xsim.dir", ".Xil", "xsim_work", $LOG_DIR)
    foreach ($d in $dirsToRemove) {
        if (Test-Path $d) {
            Remove-Item -Recurse -Force $d
            Write-Host "  Silindi: $d" -ForegroundColor Yellow
        }
    }
    $patterns = @("*.jou", "*.pb", "*.wdb", "*.vcd", "xvlog.log", "xelab.log", "xsim.log",
                   "webtalk*.jou", "webtalk*.log", "*.mem", "*.txt")
    foreach ($p in $patterns) {
        Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-Host "  Silindi: $($_.Name)" -ForegroundColor Yellow
        }
    }
    Write-Host "`n[CLEAN] Temizleme tamamlandi." -ForegroundColor Green
}

function Show-Help {
    Write-Host ""
    Write-Host ("=" * 56) -ForegroundColor Cyan
    Write-Host "  Vivado XSIM Simulasyon Scripti — Hedefler:" -ForegroundColor Cyan
    Write-Host ("=" * 56) -ForegroundColor Cyan
    Write-Host "  compile    : Kaynak dosyalari derle (xvlog)"
    Write-Host "  elaborate  : Elaboration (xelab)"
    Write-Host "  sim        : Simulasyonu calistir (xsim)"
    Write-Host "  all        : compile + elaborate + sim  [varsayilan]"
    Write-Host "  soc_test   : SoC entegrasyon testi (AXI+DMEM+DSP)"
    Write-Host "  wave       : Waveform GUI ac"
    Write-Host "  sim_vcd    : VCD kaydıyla simulasyon"
    Write-Host "  clean      : Tum ciktilari temizle"
    Write-Host "  check      : Derleme + Elaboration kontrolu (sim yok)"
    Write-Host "  help       : Bu yardim mesaji"
    Write-Host ""
    Write-Host "Kullanim:" -ForegroundColor Yellow
    Write-Host "  .\run_sim.ps1                      # all (compile+elaborate+sim)"
    Write-Host "  .\run_sim.ps1 -Target soc_test     # SoC entegrasyon testi"
    Write-Host "  .\run_sim.ps1 -Target compile      # sadece derleme"
    Write-Host "  .\run_sim.ps1 -Target clean        # temizleme"
    Write-Host ""
}

function Invoke-SocTest {
    Test-VivadoInPath
    Setup-Links
    if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR | Out-Null }

    $SOC_TB_TOP  = "tb_soc_integration"
    $SOC_SNAP    = "${SOC_TB_TOP}_snap"
    $FLIST_TB_SOC = "filelist_tb_soc.f"

    Write-Banner "SoC TEST: DSP Verilog derleniyor"
    $cmd = "xvlog $XVLOG_FLAGS_V -f $FLIST_DSP_V"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\soc_xvlog_dsp.log"
    if ($LASTEXITCODE -ne 0) { Write-Host "[HATA] DSP Verilog derleme basarisiz!" -ForegroundColor Red; exit 1 }

    Write-Banner "SoC TEST: Core + Bus + SoC RTL derleniyor"
    $cmd = "xvlog $XVLOG_FLAGS_SV -f $FLIST_CORE"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\soc_xvlog_core.log"
    if ($LASTEXITCODE -ne 0) { Write-Host "[HATA] Core derleme basarisiz!" -ForegroundColor Red; exit 1 }

    Write-Banner "SoC TEST: Testbench derleniyor"
    $cmd = "xvlog $XVLOG_FLAGS_SV -f $FLIST_TB_SOC"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\soc_xvlog_tb.log"
    if ($LASTEXITCODE -ne 0) { Write-Host "[HATA] SoC TB derleme basarisiz!" -ForegroundColor Red; exit 1 }

    Write-Banner "SoC TEST: Elaboration — $SOC_TB_TOP"
    $cmd = "xelab $XELAB_FLAGS $SOC_TB_TOP -s $SOC_SNAP"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\soc_xelab.log"
    if ($LASTEXITCODE -ne 0) { Write-Host "[HATA] Elaboration basarisiz!" -ForegroundColor Red; exit 1 }

    Write-Banner "SoC TEST: Simulasyon — $SOC_SNAP"
    $cmd = "xsim $SOC_SNAP $XSIM_FLAGS"
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression "$cmd 2>&1" | Tee-Object -FilePath "$LOG_DIR\soc_xsim.log"

    Write-Host "`n[SoC TEST] Entegrasyon testi tamamlandi." -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════
# Ana Akış
# ═══════════════════════════════════════════════════════════════

switch ($Target) {
    "compile"   { Invoke-Compile }
    "elaborate" { Invoke-Elaborate }
    "sim"       { Invoke-Sim }
    "wave"      { Invoke-Wave }
    "sim_vcd"   { Invoke-SimVcd }
    "clean"     { Invoke-Clean }
    "check"     { Invoke-Check }
    "soc_test"  { Invoke-SocTest }
    "help"      { Show-Help }
    "all"       {
        Invoke-Compile
        Invoke-Elaborate
        Invoke-Sim
    }
}
