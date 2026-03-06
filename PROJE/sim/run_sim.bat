@echo off
REM ═══════════════════════════════════════════════════════════════
REM run_sim.bat — Vivado XSIM Simulasyon Scripti (Windows CMD)
REM Kullanim:
REM   run_sim.bat              → compile + elaborate + sim
REM   run_sim.bat compile      → Sadece derleme
REM   run_sim.bat elaborate    → Sadece elaboration
REM   run_sim.bat sim          → Sadece simulasyon
REM   run_sim.bat wave         → Waveform GUI
REM   run_sim.bat clean        → Temizleme
REM
REM NOT: Vivado bin dizini PATH'te olmali.
REM ═══════════════════════════════════════════════════════════════

set TB_TOP=tb_rv_all
set SNAPSHOT=%TB_TOP%_snap
set LOG_DIR=logs
set TB_DATA_DIR=..\tb

set FLIST_CORE=filelist_core.f
set FLIST_DSP_V=filelist_dsp_verilog.f
set FLIST_TB=filelist_tb.f

set XVLOG_FLAGS_SV=--sv --incr --relax -L work
set XVLOG_FLAGS_V=--incr --relax -L work
set XELAB_FLAGS=--incr --relax --debug typical -L work
set XSIM_FLAGS=--runall --onerror quit

if "%1"=="" goto all
if "%1"=="all" goto all
if "%1"=="compile" goto compile
if "%1"=="elaborate" goto elaborate
if "%1"=="sim" goto sim
if "%1"=="check" goto check
if "%1"=="soc_test" goto soc_test
if "%1"=="wave" goto wave
if "%1"=="clean" goto clean
if "%1"=="help" goto help
echo [HATA] Bilinmeyen hedef: %1
goto help

:all
call :compile
if errorlevel 1 goto :eof
call :elaborate
if errorlevel 1 goto :eof
call :sim
goto :eof

:check
call :compile
if errorlevel 1 goto :eof
call :elaborate
if errorlevel 1 goto :eof
echo ========================================================
echo [CHECK] Derleme + Elaboration basarili!
echo         RTL syntax/elaboration hatalari yok.
echo ========================================================
goto :eof

:setup_links
echo [SETUP] tb/ dizinindeki mem/log dosyalari kopyalaniyor...
if exist "%TB_DATA_DIR%\*.mem" copy /Y "%TB_DATA_DIR%\*.mem" . >nul 2>&1
if exist "%TB_DATA_DIR%\*.txt" copy /Y "%TB_DATA_DIR%\*.txt" . >nul 2>&1
goto :eof

:compile
call :setup_links
if not exist %LOG_DIR% mkdir %LOG_DIR%
echo ========================================================
echo [XVLOG] DSP Verilog dosyalari derleniyor...
echo ========================================================
xvlog %XVLOG_FLAGS_V% -f %FLIST_DSP_V% -log %LOG_DIR%\xvlog_dsp.log
if errorlevel 1 (
    echo [HATA] DSP Verilog derleme basarisiz!
    exit /b 1
)

echo ========================================================
echo [XVLOG] Core + Bus + SoC (SystemVerilog) derleniyor...
echo ========================================================
xvlog %XVLOG_FLAGS_SV% -f %FLIST_CORE% -log %LOG_DIR%\xvlog_core.log
if errorlevel 1 (
    echo [HATA] Core derleme basarisiz!
    exit /b 1
)

echo ========================================================
echo [XVLOG] Testbench derleniyor...
echo ========================================================
xvlog %XVLOG_FLAGS_SV% -f %FLIST_TB% -log %LOG_DIR%\xvlog_tb.log
if errorlevel 1 (
    echo [HATA] TB derleme basarisiz!
    exit /b 1
)

echo [XVLOG] Derleme tamamlandi.
goto :eof

:elaborate
if not exist %LOG_DIR% mkdir %LOG_DIR%
echo ========================================================
echo [XELAB] Elaboration: %TB_TOP% -^> %SNAPSHOT%
echo ========================================================
xelab %XELAB_FLAGS% %TB_TOP% -s %SNAPSHOT% -log %LOG_DIR%\xelab.log
if errorlevel 1 (
    echo [HATA] Elaboration basarisiz!
    exit /b 1
)
echo [XELAB] Elaboration tamamlandi.
goto :eof

:sim
if not exist %LOG_DIR% mkdir %LOG_DIR%
echo ========================================================
echo [XSIM] Simulasyon baslatiliyor: %SNAPSHOT%
echo ========================================================
xsim %SNAPSHOT% %XSIM_FLAGS% -log %LOG_DIR%\xsim.log
echo [XSIM] Simulasyon tamamlandi.
goto :eof

:soc_test
set SOC_TB_TOP=tb_soc_integration
set SOC_SNAP=%SOC_TB_TOP%_snap
set FLIST_TB_SOC=filelist_tb_soc.f
call :setup_links
if not exist %LOG_DIR% mkdir %LOG_DIR%

echo ========================================================
echo [SoC TEST] DSP Verilog derleniyor...
echo ========================================================
xvlog %XVLOG_FLAGS_V% -f %FLIST_DSP_V% -log %LOG_DIR%\soc_xvlog_dsp.log
if errorlevel 1 (
    echo [HATA] DSP Verilog derleme basarisiz!
    exit /b 1
)

echo ========================================================
echo [SoC TEST] Core + Bus + SoC RTL derleniyor...
echo ========================================================
xvlog %XVLOG_FLAGS_SV% -f %FLIST_CORE% -log %LOG_DIR%\soc_xvlog_core.log
if errorlevel 1 (
    echo [HATA] Core derleme basarisiz!
    exit /b 1
)

echo ========================================================
echo [SoC TEST] SoC Testbench derleniyor...
echo ========================================================
xvlog %XVLOG_FLAGS_SV% -f %FLIST_TB_SOC% -log %LOG_DIR%\soc_xvlog_tb.log
if errorlevel 1 (
    echo [HATA] SoC TB derleme basarisiz!
    exit /b 1
)

echo ========================================================
echo [SoC TEST] Elaboration: %SOC_TB_TOP% -^> %SOC_SNAP%
echo ========================================================
xelab %XELAB_FLAGS% %SOC_TB_TOP% -s %SOC_SNAP% -log %LOG_DIR%\soc_xelab.log
if errorlevel 1 (
    echo [HATA] Elaboration basarisiz!
    exit /b 1
)

echo ========================================================
echo [SoC TEST] Simulasyon baslatiliyor: %SOC_SNAP%
echo ========================================================
xsim %SOC_SNAP% %XSIM_FLAGS% -log %LOG_DIR%\soc_xsim.log
echo [SoC TEST] Entegrasyon testi tamamlandi.
goto :eof

:wave
echo [XSIM] Waveform GUI aciliyor...
start xsim %SNAPSHOT% --gui
goto :eof

:clean
echo [CLEAN] Temizleniyor...
if exist xsim.dir  rmdir /s /q xsim.dir
if exist .Xil      rmdir /s /q .Xil
if exist xsim_work rmdir /s /q xsim_work
if exist %LOG_DIR%  rmdir /s /q %LOG_DIR%
del /q *.jou *.pb *.wdb *.vcd 2>nul
del /q xvlog.log xelab.log xsim.log 2>nul
del /q webtalk*.jou webtalk*.log 2>nul
del /q *.mem *.txt 2>nul
echo [CLEAN] Temizleme tamamlandi.
goto :eof

:help
echo ========================================================
echo  Vivado XSIM Simulasyon Scripti — Hedefler:
echo ========================================================
echo   compile    : Kaynak dosyalari derle (xvlog)
echo   elaborate  : Elaboration (xelab)
echo   sim        : Simulasyonu calistir (xsim)
echo   all        : compile + elaborate + sim  [varsayilan]
echo   soc_test   : SoC entegrasyon testi (AXI+DMEM+DSP)
echo   wave       : Waveform GUI ac
echo   clean      : Tum ciktilari temizle
echo   help       : Bu yardim mesaji
echo ========================================================
echo.
echo Kullanim:
echo   run_sim.bat              (compile+elaborate+sim)
echo   run_sim.bat compile      (sadece derleme)
echo   run_sim.bat clean        (temizleme)
goto :eof
