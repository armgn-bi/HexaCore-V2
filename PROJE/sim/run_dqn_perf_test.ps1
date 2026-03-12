# ─────────────────────────────────────────────────────
# run_dqn_perf_test.ps1 — DQN Performans Testi Runner
# Kullanim: powershell -ExecutionPolicy Bypass -File run_dqn_perf_test.ps1
# ─────────────────────────────────────────────────────

Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  DQN Performans Testi — Derleme ve Calistirma"         -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Calisan dizinde oldugumuzu kontrol et
$simDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $simDir

# Adim 1: Derleme (xvlog)
Write-Host "[1/3] SystemVerilog dosyalari derleniyor..." -ForegroundColor Yellow
$compileResult = & xvlog --sv -f filelist_dqn_perf.f 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "HATA: Derleme basarisiz!" -ForegroundColor Red
    Write-Host $compileResult
    exit 1
}
Write-Host "  Derleme basarili." -ForegroundColor Green

# Adim 2: Elaboration (xelab)
Write-Host "[2/3] Elaboration yapiliyor..." -ForegroundColor Yellow
$elabResult = & xelab tb_dqn_performance -s dqn_perf_sim -timescale 1ns/1ps 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "HATA: Elaboration basarisiz!" -ForegroundColor Red
    Write-Host $elabResult
    exit 1
}
Write-Host "  Elaboration basarili." -ForegroundColor Green

# Adim 3: Simulasyon (xsim)
Write-Host "[3/3] Simulasyon calistiriliyor..." -ForegroundColor Yellow
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "dqn_perf_result_${timestamp}.log"

& xsim dqn_perf_sim -R | Tee-Object -FilePath $logFile

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Simulasyon tamamlandi. Log dosyasi: $logFile"         -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
