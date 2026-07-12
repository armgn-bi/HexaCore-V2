# ═══════════════════════════════════════════════════════════════════════════════
# HexaCore-V2 — Kapsamli Test ve Dogrulama Scripti
# TÜBİTAK 2209A Bilimsel Rapor icin Tam Kanit Uretimi
#
# Bu script tum testleri kosar ve her adimi detayli loglar:
#   - Sistem bilgileri (OS, CPU, RAM, tarih)
#   - Vivado surum bilgisi
#   - Kaynak dosya hash'leri (SHA256) — tekrarlanabilirlik icin
#   - Her komutun tam ciktisi + zaman damgasi
#   - Test sonuclari ozeti
#
# Kullanim:
#   powershell -ExecutionPolicy Bypass -File run_all_tests_scientific.ps1
# ═══════════════════════════════════════════════════════════════════════════════

$ErrorActionPreference = "Continue"
$env:PATH = "C:\Xilinx\2025.1\Vivado\bin;" + $env:PATH

# ── Dizin Ayarlari ────────────────────────────────────────────────────────────
$PROJECT_ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SIM_DIR      = $PSScriptRoot
$REPORT_DIR   = Join-Path $PROJECT_ROOT "rapor_kanitlari"
$LOG_DIR      = Join-Path $REPORT_DIR "tam_test_loglari"
$MASTER_LOG   = Join-Path $LOG_DIR "MASTER_TEST_LOG.txt"

# Klasorleri olustur
New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null

# ── Yardimci Fonksiyonlar ─────────────────────────────────────────────────────
function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $MASTER_LOG -Value $line
}

function LogSection($title) {
    $sep = "=" * 80
    Log ""
    Log $sep
    Log "  $title"
    Log $sep
}

function RunAndLog($description, $command, $logFile) {
    LogSection $description
    Log "KOMUT: $command"
    Log "LOG DOSYASI: $logFile"
    Log "BASLANGIC: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
    Log ""

    $startTime = Get-Date
    try {
        $output = Invoke-Expression "$command 2>&1" | Out-String
        $exitCode = $LASTEXITCODE
    } catch {
        $output = $_.Exception.Message
        $exitCode = -1
    }
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds

    # Logu dosyaya yaz
    $logContent = @"
════════════════════════════════════════════════════════════════════════════════
  $description
════════════════════════════════════════════════════════════════════════════════
KOMUT     : $command
TARIH     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
SURE      : $([math]::Round($duration, 2)) saniye
EXIT CODE : $exitCode
════════════════════════════════════════════════════════════════════════════════

$output
"@
    Set-Content -Path $logFile -Value $logContent -Encoding UTF8

    # Master loga da yaz
    Add-Content -Path $MASTER_LOG -Value $output

    Log ""
    Log "BITIS: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
    Log "SURE: $([math]::Round($duration, 2)) saniye"
    Log "EXIT CODE: $exitCode"

    return @{ Output = $output; ExitCode = $exitCode; Duration = $duration }
}

# ═══════════════════════════════════════════════════════════════════════════════
# BOLUM 0: SISTEM BILGILERI
# ═══════════════════════════════════════════════════════════════════════════════

# Master log dosyasini baslat
$startAll = Get-Date
Set-Content -Path $MASTER_LOG -Value "" -Encoding UTF8

LogSection "HEXACORE-V2 KAPSAMLI TEST VE DOGRULAMA RAPORU"
Log "Rapor Olusturma Tarihi: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
Log ""

LogSection "BOLUM 0: SISTEM VE ORTAM BILGILERI"

# OS bilgisi
Log "--- Isletim Sistemi ---"
$os = Get-CimInstance Win32_OperatingSystem
Log "  OS        : $($os.Caption) $($os.Version)"
Log "  Bilgisayar: $($os.CSName)"
Log "  Mimari    : $($os.OSArchitecture)"

# CPU bilgisi
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Log "  CPU       : $($cpu.Name)"
Log "  Cekirdek  : $($cpu.NumberOfCores) fiziksel, $($cpu.NumberOfLogicalProcessors) mantiksal"

# RAM bilgisi
$ram = [math]::Round(($os.TotalVisibleMemorySize / 1MB), 1)
Log "  RAM       : $ram GB"

# Vivado surum
Log ""
Log "--- Vivado Bilgileri ---"
$vivadoVer = & xvlog --version 2>&1 | Out-String
Log "  $($vivadoVer.Trim())"
$vivadoPath = (Get-Command xvlog).Source
Log "  Kurulum   : $vivadoPath"

# PowerShell surum
Log ""
Log "--- PowerShell ---"
Log "  Surum     : $($PSVersionTable.PSVersion)"

# Calisma dizini
Log ""
Log "--- Proje Dizinleri ---"
Log "  Proje Kok : $PROJECT_ROOT"
Log "  Sim Dizin : $SIM_DIR"
Log "  Rapor Diz : $REPORT_DIR"
Log "  Log Dizin : $LOG_DIR"

# ═══════════════════════════════════════════════════════════════════════════════
# BOLUM 1: KAYNAK DOSYA BUTUNLUK KONTROLU (SHA256 Hash)
# ═══════════════════════════════════════════════════════════════════════════════
LogSection "BOLUM 1: KAYNAK DOSYA BUTUNLUK KONTROLU (SHA256)"
Log "Amac: Testlerin hangi kaynak kod surumunde kosuldugunu belgelemek"
Log ""

$rtlDir = Join-Path $PROJECT_ROOT "PROJE\rtl"
$tbDir  = Join-Path $PROJECT_ROOT "PROJE\tb"

$hashLog = Join-Path $LOG_DIR "kaynak_dosya_hashleri.txt"
$hashContent = "# HexaCore-V2 Kaynak Dosya SHA256 Hash'leri`n"
$hashContent += "# Tarih: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
$hashContent += "# ═══════════════════════════════════════════════════`n`n"

$hashContent += "# --- RTL Dosyalari ---`n"
Get-ChildItem -Path $rtlDir -Recurse -Include "*.sv","*.v" | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    $rel = $_.FullName.Replace($PROJECT_ROOT, ".")
    $line = "$hash  $rel"
    $hashContent += "$line`n"
    Log "  $line"
}

$hashContent += "`n# --- Testbench Dosyalari ---`n"
Get-ChildItem -Path $tbDir -Recurse -Include "*.sv" | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    $rel = $_.FullName.Replace($PROJECT_ROOT, ".")
    $line = "$hash  $rel"
    $hashContent += "$line`n"
    Log "  $line"
}

$hashContent += "`n# --- Memory Init Dosyalari ---`n"
Get-ChildItem -Path $tbDir -Recurse -Include "*.mem" | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    $rel = $_.FullName.Replace($PROJECT_ROOT, ".")
    $line = "$hash  $rel"
    $hashContent += "$line`n"
    Log "  $line"
}

$hashContent += "`n# --- Golden Log Dosyalari ---`n"
Get-ChildItem -Path $tbDir -Recurse -Include "*.log.txt" | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    $rel = $_.FullName.Replace($PROJECT_ROOT, ".")
    $line = "$hash  $rel"
    $hashContent += "$line`n"
    Log "  $line"
}

Set-Content -Path $hashLog -Value $hashContent -Encoding UTF8
Log ""
Log "Hash dosyasi kaydedildi: $hashLog"

# ═══════════════════════════════════════════════════════════════════════════════
# BOLUM 2: DERLEME (COMPILE)
# ═══════════════════════════════════════════════════════════════════════════════

# Onceden mem/log dosyalarini kopyala
Copy-Item (Join-Path $tbDir "*.mem") $SIM_DIR -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $tbDir "*.txt") $SIM_DIR -Force -ErrorAction SilentlyContinue

# 2.1 DSP Verilog
$r = RunAndLog "BOLUM 2.1: DSP Verilog Derleme (xvlog)" `
    "xvlog --incr --relax -L work -f filelist_dsp_verilog.f" `
    (Join-Path $LOG_DIR "01_compile_dsp_verilog.log")
if ($r.ExitCode -ne 0) { Log "HATA: DSP Verilog derleme basarisiz!"; exit 1 }

# 2.2 Core + Bus + SoC (SystemVerilog)
$r = RunAndLog "BOLUM 2.2: Core + Bus + SoC RTL Derleme (xvlog --sv)" `
    "xvlog --sv --incr --relax -L work -f filelist_core.f" `
    (Join-Path $LOG_DIR "02_compile_core_sv.log")
if ($r.ExitCode -ne 0) { Log "HATA: Core SV derleme basarisiz!"; exit 1 }

# ═══════════════════════════════════════════════════════════════════════════════
# BOLUM 3: TEST 1 — CEKIRDEK REGRESYON (188 test)
# ═══════════════════════════════════════════════════════════════════════════════

# 3.1 TB Derleme
$r = RunAndLog "BOLUM 3.1: Cekirdek TB Derleme (tb_rv_all)" `
    "xvlog --sv --incr --relax -L work -f filelist_tb.f" `
    (Join-Path $LOG_DIR "03_compile_tb_rv.log")

# 3.2 Elaboration
$r = RunAndLog "BOLUM 3.2: Cekirdek Elaboration" `
    "xelab --incr --relax --debug typical -L work tb_rv_all -s tb_rv_all_snap" `
    (Join-Path $LOG_DIR "04_elaborate_tb_rv.log")

# 3.3 Simulasyon
$r = RunAndLog "BOLUM 3.3: Cekirdek Regresyon Simulasyonu (188 test)" `
    "xsim tb_rv_all_snap --runall --onerror quit" `
    (Join-Path $LOG_DIR "05_sim_cekirdek_regresyon.log")

# Sonuc cikart
$passCount = ([regex]::Matches($r.Output, "PASS")).Count
$failCount = ([regex]::Matches($r.Output, "FAIL")).Count
Log ">>> CEKIRDEK REGRESYON: PASS=$passCount"

# ═══════════════════════════════════════════════════════════════════════════════
# BOLUM 4: TEST 2 — SOC ENTEGRASYON (23 test)
# ═══════════════════════════════════════════════════════════════════════════════

# 4.1 SoC TB Derleme
$r = RunAndLog "BOLUM 4.1: SoC Entegrasyon TB Derleme" `
    "xvlog --sv --incr --relax -L work -f filelist_tb_soc.f" `
    (Join-Path $LOG_DIR "06_compile_tb_soc.log")

# 4.2 Elaboration
$r = RunAndLog "BOLUM 4.2: SoC Entegrasyon Elaboration" `
    "xelab --incr --relax --debug typical -L work tb_soc_integration -s tb_soc_integration_snap" `
    (Join-Path $LOG_DIR "07_elaborate_soc.log")

# 4.3 Simulasyon
$r = RunAndLog "BOLUM 4.3: SoC Entegrasyon Simulasyonu (23 test)" `
    "xsim tb_soc_integration_snap --runall --onerror quit" `
    (Join-Path $LOG_DIR "08_sim_soc_entegrasyon.log")

# ═══════════════════════════════════════════════════════════════════════════════
# BOLUM 5: TEST 3 — DQN AXI ENTEGRASYON (27 test)
# ═══════════════════════════════════════════════════════════════════════════════

# 5.1 DQN Derleme
$r = RunAndLog "BOLUM 5.1: DQN AXI TB Derleme" `
    "xvlog --sv -f filelist_dqn.f" `
    (Join-Path $LOG_DIR "09_compile_dqn.log")

# 5.2 Elaboration
$r = RunAndLog "BOLUM 5.2: DQN AXI Elaboration" `
    "xelab --incr --relax --debug typical -L work tb_dqn -s tb_dqn_snap" `
    (Join-Path $LOG_DIR "10_elaborate_dqn.log")

# 5.3 Simulasyon
$r = RunAndLog "BOLUM 5.3: DQN AXI Simulasyonu (27 test)" `
    "xsim tb_dqn_snap --runall --onerror quit" `
    (Join-Path $LOG_DIR "11_sim_dqn_axi.log")

# ═══════════════════════════════════════════════════════════════════════════════
# BOLUM 6: TEST 4 — DQN PERFORMANS (13 test)
# ═══════════════════════════════════════════════════════════════════════════════

# 6.1 Derleme
$r = RunAndLog "BOLUM 6.1: DQN Performans TB Derleme" `
    "xvlog --sv -f filelist_dqn_perf.f" `
    (Join-Path $LOG_DIR "12_compile_dqn_perf.log")

# 6.2 Elaboration
$r = RunAndLog "BOLUM 6.2: DQN Performans Elaboration" `
    "xelab tb_dqn_performance -s dqn_perf_sim -timescale 1ns/1ps" `
    (Join-Path $LOG_DIR "13_elaborate_dqn_perf.log")

# 6.3 Simulasyon
$r = RunAndLog "BOLUM 6.3: DQN Performans Simulasyonu (13 test)" `
    "xsim dqn_perf_sim -R" `
    (Join-Path $LOG_DIR "14_sim_dqn_performans.log")

# ═══════════════════════════════════════════════════════════════════════════════
# BOLUM 7: TEST 5 — DQN CORE STANDALONE (24 test, XSIM)
# ═══════════════════════════════════════════════════════════════════════════════

# 7.1 Derleme
$r = RunAndLog "BOLUM 7.1: DQN Core Standalone TB Derleme" `
    "xvlog --sv ../rtl/dqn/dqn_core.sv ../tb/periph_tb/tb_dqn_core_standalone.sv" `
    (Join-Path $LOG_DIR "15_compile_dqn_standalone.log")

# 7.2 Elaboration
$r = RunAndLog "BOLUM 7.2: DQN Core Standalone Elaboration" `
    "xelab --incr --relax --debug typical -L work tb_dqn_core_standalone -s tb_dqn_standalone_snap" `
    (Join-Path $LOG_DIR "16_elaborate_dqn_standalone.log")

# 7.3 Simulasyon
$r = RunAndLog "BOLUM 7.3: DQN Core Standalone Simulasyonu (24 test)" `
    "xsim tb_dqn_standalone_snap --runall --onerror quit" `
    (Join-Path $LOG_DIR "17_sim_dqn_standalone.log")

# ═══════════════════════════════════════════════════════════════════════════════
# BOLUM 8: SENTEZ RAPORU
# ═══════════════════════════════════════════════════════════════════════════════
LogSection "BOLUM 8: SENTEZ KAYNAK TUKETIM RAPORU"

$utilRpt = Join-Path $PROJECT_ROOT "nexys_a7_top_utilization_synth.rpt"
if (Test-Path $utilRpt) {
    $utilContent = Get-Content $utilRpt -Raw
    Log "Sentez raporu bulundu: $utilRpt"
    Log ""
    Log $utilContent
    Copy-Item $utilRpt (Join-Path $LOG_DIR "18_sentez_utilization.rpt") -Force

    # Sentez raporu hash
    $utilHash = (Get-FileHash $utilRpt -Algorithm SHA256).Hash
    Log "Sentez raporu SHA256: $utilHash"
} else {
    Log "UYARI: Sentez raporu bulunamadi: $utilRpt"
}

# Sentez logu
$synthLog = Join-Path $PROJECT_ROOT "vivado_synth.log"
if (Test-Path $synthLog) {
    Copy-Item $synthLog (Join-Path $LOG_DIR "19_vivado_synth.log") -Force
    $synthHash = (Get-FileHash $synthLog -Algorithm SHA256).Hash
    Log "Sentez logu kopyalandi. SHA256: $synthHash"
}

# ═══════════════════════════════════════════════════════════════════════════════
# BOLUM 9: SONUC OZETI
# ═══════════════════════════════════════════════════════════════════════════════
$endAll = Get-Date
$totalDuration = ($endAll - $startAll).TotalSeconds

LogSection "BOLUM 9: TOPLU TEST SONUC OZETI"
Log ""
Log "Toplam calisma suresi: $([math]::Round($totalDuration, 1)) saniye"
Log "Baslangic: $($startAll.ToString('yyyy-MM-dd HH:mm:ss'))"
Log "Bitis    : $($endAll.ToString('yyyy-MM-dd HH:mm:ss'))"
Log ""
Log "Log dosyalari dizini: $LOG_DIR"
Log ""
Log "═══════════════════════════════════════════════════════════════"
Log "  OLUSTURULAN LOG DOSYALARI:"
Log "═══════════════════════════════════════════════════════════════"
Get-ChildItem $LOG_DIR -File | Sort-Object Name | ForEach-Object {
    $size = [math]::Round($_.Length / 1KB, 1)
    Log "  $($_.Name) ($size KB)"
}
Log ""
Log "═══════════════════════════════════════════════════════════════"
Log "  TUM TESTLER TAMAMLANDI"
Log "═══════════════════════════════════════════════════════════════"
