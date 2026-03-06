# ═══════════════════════════════════════════════════════════════
# Makefile — Vivado XSIM Simülasyon Akışı
# Kullanım:
#   make compile    → Kaynak dosyaları derle (xvlog)
#   make elaborate  → Elaboration (xelab)
#   make sim        → Simülasyonu çalıştır (xsim)
#   make all        → compile + elaborate + sim
#   make wave       → Simülasyon sonrası waveform aç
#   make clean      → Tüm çıktıları temizle
#
# Gereksinim: Vivado bin dizini PATH'te olmalı.
#   Örnek: set PATH=%XILINX_VIVADO%\bin;%PATH%
#
# NOT: Bu Makefile, "sim/" dizininde çalıştırılmalıdır.
#   cd sim && make all
# ═══════════════════════════════════════════════════════════════

# ── Araç Ayarları ─────────────────────────────────────────────
XVLOG       := xvlog
XELAB       := xelab
XSIM        := xsim

# ── Top-level testbench modülü ────────────────────────────────
TB_TOP      := tb_rv_all

# ── Snapshot adı (elaborate çıktısı) ─────────────────────────
SNAPSHOT    := $(TB_TOP)_snap

# ── Çalışma dizini ────────────────────────────────────────────
WORK_DIR    := xsim_work
LOG_DIR     := logs

# ── Filelist'ler ──────────────────────────────────────────────
FLIST_CORE  := filelist_core.f
FLIST_DSP_V := filelist_dsp_verilog.f
FLIST_TB    := filelist_tb.f

# ── Derleme bayrakları ────────────────────────────────────────
XVLOG_FLAGS_SV := --sv --incr --relax -L work
XVLOG_FLAGS_V  := --incr --relax -L work
XELAB_FLAGS    := --incr --relax --debug typical -L work
XSIM_FLAGS     := --runall --onerror quit

# ── Testbench mem/log dosyalarının bulunduğu dizin ────────────
TB_DATA_DIR := ../tb

# ═══════════════════════════════════════════════════════════════
# Hedefler
# ═══════════════════════════════════════════════════════════════

.PHONY: all compile elaborate sim sim_vcd wave clean help setup_links check soc_test

all: compile elaborate sim

check: compile elaborate
	@echo ""
	@echo "════════════════════════════════════════════════"
	@echo "[CHECK] Derleme + Elaboration basarili!"
	@echo "        RTL syntax/elaboration hatalari yok."
	@echo "════════════════════════════════════════════════"

help:
	@echo "═══════════════════════════════════════════════════"
	@echo " Vivado XSIM Makefile — Kullanilabilir hedefler:"
	@echo "═══════════════════════════════════════════════════"
	@echo "  make compile    : Kaynak dosyalari derle (xvlog)"
	@echo "  make elaborate  : Elaboration (xelab)"
	@echo "  make sim        : Simulasyonu calistir (xsim)"
	@echo "  make all        : compile + elaborate + sim"
	@echo "  make soc_test   : SoC entegrasyon testi (AXI+DMEM+DSP)"
	@echo "  make wave       : Waveform dosyasini ac (xsim GUI)"
	@echo "  make clean      : Tum ciktilari temizle"
	@echo "═══════════════════════════════════════════════════"

# ── Mem/log dosyalarına sembolik bağ oluştur ──────────────────
# XSIM, sim çalışma dizininde mem dosyalarını arar.
setup_links:
	@echo "[SETUP] tb dizinindeki mem/log dosyalari kopyalaniyor..."
	@cp -f $(TB_DATA_DIR)/*.mem . 2>/dev/null || true
	@cp -f $(TB_DATA_DIR)/*.txt . 2>/dev/null || true
	@cp -f $(TB_DATA_DIR)/*.log . 2>/dev/null || true

# ── Derleme: SystemVerilog + Verilog ─────────────────────────
compile: setup_links
	@mkdir -p $(LOG_DIR)
	@echo "════════════════════════════════════════════════"
	@echo "[XVLOG] DSP Verilog dosyalari derleniyor..."
	@echo "════════════════════════════════════════════════"
	$(XVLOG) $(XVLOG_FLAGS_V) -f $(FLIST_DSP_V) 2>&1 | tee $(LOG_DIR)/xvlog_dsp.log
	@echo ""
	@echo "════════════════════════════════════════════════"
	@echo "[XVLOG] Core + Bus + SoC (SystemVerilog) derleniyor..."
	@echo "════════════════════════════════════════════════"
	$(XVLOG) $(XVLOG_FLAGS_SV) -f $(FLIST_CORE) 2>&1 | tee $(LOG_DIR)/xvlog_core.log
	@echo ""
	@echo "════════════════════════════════════════════════"
	@echo "[XVLOG] Testbench derleniyor..."
	@echo "════════════════════════════════════════════════"
	$(XVLOG) $(XVLOG_FLAGS_SV) -f $(FLIST_TB) 2>&1 | tee $(LOG_DIR)/xvlog_tb.log
	@echo ""
	@echo "[XVLOG] Derleme tamamlandi."

# ── Elaboration ──────────────────────────────────────────────
elaborate: 
	@mkdir -p $(LOG_DIR)
	@echo "════════════════════════════════════════════════"
	@echo "[XELAB] Elaboration: $(TB_TOP) -> $(SNAPSHOT)"
	@echo "════════════════════════════════════════════════"
	$(XELAB) $(XELAB_FLAGS) $(TB_TOP) -s $(SNAPSHOT) 2>&1 | tee $(LOG_DIR)/xelab.log
	@echo "[XELAB] Elaboration tamamlandi."

# ── Simülasyon ───────────────────────────────────────────────
sim:
	@mkdir -p $(LOG_DIR)
	@echo "════════════════════════════════════════════════"
	@echo "[XSIM] Simulasyon baslatiliyor: $(SNAPSHOT)"
	@echo "════════════════════════════════════════════════"
	$(XSIM) $(SNAPSHOT) $(XSIM_FLAGS) 2>&1 | tee $(LOG_DIR)/xsim.log
	@echo "[XSIM] Simulasyon tamamlandi."

# ── Waveform açma (GUI modunda) ──────────────────────────────
wave:
	@echo "[XSIM] Waveform GUI aciliyor..."
	$(XSIM) $(SNAPSHOT) --gui &

# ── Tcl batch simülasyon (VCD kaydı ile) ─────────────────────
sim_vcd:
	@mkdir -p $(LOG_DIR)
	@echo "════════════════════════════════════════════════"
	@echo "[XSIM] VCD kaydıyla simulasyon baslatiliyor..."
	@echo "════════════════════════════════════════════════"
	$(XSIM) $(SNAPSHOT) --tclbatch xsim_run.tcl 2>&1 | tee $(LOG_DIR)/xsim_vcd.log

# ── SoC Entegrasyon Testi ─────────────────────────────────────
# Bağımsız akış: compile + elaborate + sim (tb_soc_integration)
SOC_TB_TOP   := tb_soc_integration
SOC_SNAPSHOT := $(SOC_TB_TOP)_snap
FLIST_TB_SOC := filelist_tb_soc.f

soc_test: setup_links
	@mkdir -p $(LOG_DIR)
	@echo "════════════════════════════════════════════════"
	@echo "[SoC TEST] DSP Verilog derleniyor..."
	@echo "════════════════════════════════════════════════"
	$(XVLOG) $(XVLOG_FLAGS_V) -f $(FLIST_DSP_V) 2>&1 | tee $(LOG_DIR)/soc_xvlog_dsp.log
	@echo ""
	@echo "════════════════════════════════════════════════"
	@echo "[SoC TEST] Core + Bus + SoC RTL derleniyor..."
	@echo "════════════════════════════════════════════════"
	$(XVLOG) $(XVLOG_FLAGS_SV) -f $(FLIST_CORE) 2>&1 | tee $(LOG_DIR)/soc_xvlog_core.log
	@echo ""
	@echo "════════════════════════════════════════════════"
	@echo "[SoC TEST] SoC Testbench derleniyor..."
	@echo "════════════════════════════════════════════════"
	$(XVLOG) $(XVLOG_FLAGS_SV) -f $(FLIST_TB_SOC) 2>&1 | tee $(LOG_DIR)/soc_xvlog_tb.log
	@echo ""
	@echo "════════════════════════════════════════════════"
	@echo "[SoC TEST] Elaboration: $(SOC_TB_TOP) -> $(SOC_SNAPSHOT)"
	@echo "════════════════════════════════════════════════"
	$(XELAB) $(XELAB_FLAGS) $(SOC_TB_TOP) -s $(SOC_SNAPSHOT) 2>&1 | tee $(LOG_DIR)/soc_xelab.log
	@echo ""
	@echo "════════════════════════════════════════════════"
	@echo "[SoC TEST] Simulasyon baslatiliyor: $(SOC_SNAPSHOT)"
	@echo "════════════════════════════════════════════════"
	$(XSIM) $(SOC_SNAPSHOT) $(XSIM_FLAGS) 2>&1 | tee $(LOG_DIR)/soc_xsim.log
	@echo "[SoC TEST] Entegrasyon testi tamamlandi."

# ── Temizleme ────────────────────────────────────────────────
clean:
	@echo "[CLEAN] Temizleniyor..."
	rm -rf xsim.dir .Xil xsim_work
	rm -rf $(LOG_DIR)
	rm -f  *.jou *.log *.pb *.wdb *.vcd
	rm -f  webtalk*.jou webtalk*.log
	rm -f  xvlog.log xvlog.pb xelab.log xelab.pb xsim.log
	rm -f  *.mem *.txt 
	@echo "[CLEAN] Temizleme tamamlandi."
