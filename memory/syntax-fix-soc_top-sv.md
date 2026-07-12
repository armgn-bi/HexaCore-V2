Fixed syntax error in rtl/top/soc_top.sv: Added missing comma after .s_axi_rready_i port connection in axi_i2c instantiation (line 423).

Previously caused "[HDL 9-1206] Syntax error near '.'" and "[Synth 8-2716] syntax error near '.'" errors during synthesis.