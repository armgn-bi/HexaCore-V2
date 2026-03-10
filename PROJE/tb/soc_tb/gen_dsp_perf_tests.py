#!/usr/bin/env python3
# filepath: tb/soc_tb/gen_dsp_perf_tests.py
# ═══════════════════════════════════════════════════════════════
# DSP Performans Testi — RISC-V Assembly → .mem Dosya Üreteci
#
# Her test programı şu registerleri doldurur:
#   x28 (t3) = N (sample sayısı)
#   x29 (t4) = test_type (0=CPU-only, 1=DSP-accelerated)
#   x30 (t5) = first output sample
#   x31 (t6) = last output sample
#
# Bellek düzeni:
#   IMEM: 0x8000_0000 (program)
#   İç DMEM: 0x8000_0000 base, giriş verileri → offset 0x4000'den itibaren
#   AXI DMEM: 0x8001_0000 (çıkış verisi depolanır — CPU-only modda)
#   DSP: 0x4000_1000 (CTRL=0x00, STATUS=0x04, DATA_IN=0x08, DATA_OUT_L=0x0C)
#
# 11-TAP FIR katsayıları (Q0.16 → sfix16_En16):
#   h = [0, -580, -2122, 2091, 18473, 29232, 18473, 2091, -2122, -580, 0]
#   (16-bit signed integer representations)
# ═══════════════════════════════════════════════════════════════

import struct
import os

# FIR katsayıları (signed 16-bit, Q0.16 formatında tam sayı değerleri)
# FilterCoef.v'den okundu
FIR_COEFS = [0, -290, -1098, 2091, 18473, 29232, 18473, 2091, -1098, -290, 0]
# İkinin tümleyenine çevirelim (düzeltilmiş — binary'den okuma)
# 0000000000000000 = 0
# 1111111011011110 = -290 (two's complement of 0xFEDE)
# 1111011110110110 = -2122 nope let me recalculate
# 1111011110110110 -> 0xFBB6 -> unsigned=64438 -> signed = 64438-65536 = -1098
# 0000100000101011 -> 0x082B -> 2091
# 0100100000101001 -> 0x4829 -> 18473
# 0111001000110000 -> 0x7230 -> 29232

FIR_COEFS_16 = [0, -290, -1098, 2091, 18473, 29232, 18473, 2091, -1098, -290, 0]
NUM_TAPS = 11

SAMPLE_SIZES = [64, 128, 256, 512, 1024, 2048, 4096, 8192]

# RISC-V instruction encoders
def r_type(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def i_type(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def s_type(imm12, rs2, rs1, funct3, opcode):
    imm_hi = (imm12 >> 5) & 0x7F
    imm_lo = imm12 & 0x1F
    return (imm_hi << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_lo << 7) | opcode

def u_type(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode

def b_type(imm13, rs2, rs1, funct3, opcode):
    # imm[12|10:5|4:1|11]
    bit12  = (imm13 >> 12) & 1
    bit11  = (imm13 >> 11) & 1
    bit10_5 = (imm13 >> 5) & 0x3F
    bit4_1  = (imm13 >> 1) & 0xF
    return (bit12 << 31) | (bit10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (bit4_1 << 8) | (bit11 << 7) | opcode

def j_type(imm21, rd, opcode):
    # imm[20|10:1|11|19:12]
    bit20    = (imm21 >> 20) & 1
    bit19_12 = (imm21 >> 12) & 0xFF
    bit11    = (imm21 >> 11) & 1
    bit10_1  = (imm21 >> 1) & 0x3FF
    return (bit20 << 31) | (bit10_1 << 21) | (bit11 << 20) | (bit19_12 << 12) | (rd << 7) | opcode

# Instruction helpers
def LUI(rd, imm20):
    return u_type(imm20, rd, 0x37)

def ADDI(rd, rs1, imm):
    return i_type(imm & 0xFFF, rs1, 0, rd, 0x13)

def ADD(rd, rs1, rs2):
    return r_type(0, rs2, rs1, 0, rd, 0x33)

def SUB(rd, rs1, rs2):
    return r_type(0x20, rs2, rs1, 0, rd, 0x33)

def AND(rd, rs1, rs2):
    return r_type(0, rs2, rs1, 7, rd, 0x33)

def OR(rd, rs1, rs2):
    return r_type(0, rs2, rs1, 6, rd, 0x33)

def XOR(rd, rs1, rs2):
    return r_type(0, rs2, rs1, 4, rd, 0x33)

def SLL(rd, rs1, rs2):
    return r_type(0, rs2, rs1, 1, rd, 0x33)

def SRL(rd, rs1, rs2):
    return r_type(0, rs2, rs1, 5, rd, 0x33)

def SRA(rd, rs1, rs2):
    return r_type(0x20, rs2, rs1, 5, rd, 0x33)

def SLLI(rd, rs1, shamt):
    return i_type(shamt & 0x1F, rs1, 1, rd, 0x13)

def SRLI(rd, rs1, shamt):
    return i_type(shamt & 0x1F, rs1, 5, rd, 0x13)

def SRAI(rd, rs1, shamt):
    return i_type(0x400 | (shamt & 0x1F), rs1, 5, rd, 0x13)

def ANDI(rd, rs1, imm):
    return i_type(imm & 0xFFF, rs1, 7, rd, 0x13)

def ORI(rd, rs1, imm):
    return i_type(imm & 0xFFF, rs1, 6, rd, 0x13)

def SLT(rd, rs1, rs2):
    return r_type(0, rs2, rs1, 2, rd, 0x33)

def SLTU(rd, rs1, rs2):
    return r_type(0, rs2, rs1, 3, rd, 0x33)

def SLTI(rd, rs1, imm):
    return i_type(imm & 0xFFF, rs1, 2, rd, 0x13)

def LW(rd, rs1, offset):
    return i_type(offset & 0xFFF, rs1, 2, rd, 0x03)

def LH(rd, rs1, offset):
    return i_type(offset & 0xFFF, rs1, 1, rd, 0x03)

def LHU(rd, rs1, offset):
    return i_type(offset & 0xFFF, rs1, 5, rd, 0x03)

def SW(rs2, rs1, offset):
    return s_type(offset & 0xFFF, rs2, rs1, 2, 0x23)

def SH(rs2, rs1, offset):
    return s_type(offset & 0xFFF, rs2, rs1, 1, 0x23)

def BEQ(rs1, rs2, offset):
    return b_type(offset & 0x1FFF, rs2, rs1, 0, 0x63)

def BNE(rs1, rs2, offset):
    return b_type(offset & 0x1FFF, rs2, rs1, 1, 0x63)

def BLT(rs1, rs2, offset):
    return b_type(offset & 0x1FFF, rs2, rs1, 4, 0x63)

def BGE(rs1, rs2, offset):
    return b_type(offset & 0x1FFF, rs2, rs1, 5, 0x63)

def BLTU(rs1, rs2, offset):
    return b_type(offset & 0x1FFF, rs2, rs1, 6, 0x63)

def JAL(rd, offset):
    return j_type(offset & 0x1FFFFF, rd, 0x6F)

def JALR(rd, rs1, offset):
    return i_type(offset & 0xFFF, rs1, 0, rd, 0x67)

def NOP():
    return ADDI(0, 0, 0)

# Register aliases
x0, x1, x2, x3, x4, x5, x6, x7 = 0, 1, 2, 3, 4, 5, 6, 7
x8, x9, x10, x11, x12, x13, x14, x15 = 8, 9, 10, 11, 12, 13, 14, 15
x16, x17, x18, x19, x20, x21, x22, x23 = 16, 17, 18, 19, 20, 21, 22, 23
x24, x25, x26, x27, x28, x29, x30, x31 = 24, 25, 26, 27, 28, 29, 30, 31

# t-regs
t0, t1, t2, t3, t4, t5, t6 = x5, x6, x7, x28, x29, x30, x31
# s-regs
s0, s1, s2, s3, s4, s5, s6, s7 = x8, x9, x18, x19, x20, x21, x22, x23
s8, s9, s10, s11 = x24, x25, x26, x27
# a-regs
a0, a1, a2, a3, a4, a5, a6, a7 = x10, x11, x12, x13, x14, x15, x16, x17

def load_imm(rd, value):
    """32-bit immediate yükleme → LUI + ADDI instruction listesi"""
    value = value & 0xFFFFFFFF
    insts = []
    if value == 0:
        insts.append(ADDI(rd, x0, 0))
    elif -2048 <= _signed32(value) <= 2047:
        insts.append(ADDI(rd, x0, value & 0xFFF))
    else:
        upper = (value + 0x800) >> 12
        lower = value - (upper << 12)
        lower = lower & 0xFFFFFFFF
        if lower >= 0x800:
            lower = lower - 0x1000
        insts.append(LUI(rd, upper & 0xFFFFF))
        if (lower & 0xFFF) != 0:
            insts.append(ADDI(rd, rd, lower & 0xFFF))
    return insts

def _signed32(v):
    v = v & 0xFFFFFFFF
    if v >= 0x80000000:
        return v - 0x100000000
    return v

def _to_hex(instr):
    return f"{instr & 0xFFFFFFFF:08X}"


# ═══════════════════════════════════════════════════════════════
# Test verileri üreteci
# Giriş: sawtooth wave (testüs sinyal — değerler -32768..32767 arasında döner)
# ═══════════════════════════════════════════════════════════════
def generate_input_data(n):
    """N adet 16-bit signed sawtooth sample üret"""
    data = []
    for i in range(n):
        # Sawtooth: -16384 ile +16384 arası, periyot 64
        val = ((i % 64) * 512) - 16384
        val = max(-32768, min(32767, val))
        data.append(val)
    return data


# ═══════════════════════════════════════════════════════════════
# CPU-only FIR Test Programı
# ═══════════════════════════════════════════════════════════════
def gen_cpu_only_fir(N):
    """
    CPU-only FIR filtre testi.
    Yazılım ile 11-TAP FIR hesaplaması yapılır.
    RV32I'de MUL yok → shift-and-add multiply subroutine kullanılır.
    
    Bellek düzeni:
      İç DMEM (0x8000_0000 base):
        0x4000-0x5FFF : Giriş verileri (halfword, her biri 2 byte)
        0x6000-0x7FFF : Çıkış verileri (word, her biri 4 byte)
        0x2000-0x200B : Katsayılar (halfword, 11 adet × 2 byte = 22 byte)
        
    Algoritma:
      for i = 0..N-1:
        acc = 0
        for k = 0..10:
          if (i-k) >= 0:
            acc += input[i-k] * coef[k]   // 16×16 → 32-bit multiply
        output[i] = acc >> 16  // Q normalizasyon (Q15 × Q16 = Q31, >> 16 → Q15)
    """
    
    code = []
    comments = []
    
    def emit(instr, comment=""):
        code.append(instr)
        comments.append(comment)
    
    def emit_list(instrs, comment=""):
        for i, inst in enumerate(instrs):
            code.append(inst)
            comments.append(comment if i == 0 else "")
    
    # Register allocation:
    # s0 (x8)  = iç DMEM base (0x8000_0000)
    # s1 (x9)  = N (sample count)
    # s2 (x18) = outer loop counter i
    # s3 (x19) = inner loop counter k
    # s4 (x20) = accumulator (32-bit)
    # s5 (x21) = temp: input sample address
    # s6 (x22) = temp: coef address
    # s7 (x23) = temp: input[i-k]
    # s8 (x24) = temp: coef[k]
    # s9 (x25) = temp: multiply result
    # s10(x26) = temp
    # s11(x27) = temp
    # t0 (x5)  = temp for multiply subroutine
    # t1 (x6)  = temp
    # t2 (x7)  = temp
    # a0 (x10) = subroutine arg/return
    # a1 (x11) = subroutine arg
    # x1 (ra)  = return address
    # t3 (x28) = N (output)
    # t4 (x29) = test_type = 0
    # t5 (x30) = first output
    # t6 (x31) = last output
    
    # ── Katsayıları iç DMEM'e yükle (0x8000_2000) ──
    emit_list(load_imm(s0, 0x80000000), "s0 = iç DMEM base")
    
    # Katsayıları tek tek yükle ve halfword olarak depola
    coef_base_offset = 0x2000
    for idx, coef in enumerate(FIR_COEFS_16):
        coef_val = coef & 0xFFFF
        emit_list(load_imm(t0, coef_val if coef >= 0 else (coef & 0xFFFF)), 
                  f"coef[{idx}] = {coef}")
        emit(SH(t0, s0, coef_base_offset + idx * 2), f"store coef[{idx}] at offset {coef_base_offset + idx*2:#x}")
    
    # ── Giriş verilerini iç DMEM'e yükle (0x8000_4000) ──
    # N adet sawtooth sample
    input_data = generate_input_data(N)
    input_base_offset = 0x4000
    
    # Veri yükleme: N büyük olabileceği için register'a yükle + loop ile store
    # Ama basitlik için doğrudan immediate ile koyalım — N <= 8192 ve her biri 2 instruction
    # Bu IMEM boyutunu çok şişirirdi. Bunun yerine basit bir formül ile üretim yapalım:
    # x[i] = ((i % 64) * 512) - 16384
    # Bu loop ile üretilebilir.
    
    emit_list(load_imm(s1, N), "s1 = N")
    emit_list(load_imm(s2, 0), "s2 = i = 0 (giriş üretimi)")
    emit_list(load_imm(t1, 64), "t1 = 64 (period)")
    emit_list(load_imm(t2, input_base_offset), "t2 = input base offset")
    emit(ADD(t2, t2, s0), "t2 = input base absolute addr")
    
    # Giriş verisi üretim döngüsü: x[i] = ((i % 64) * 512) - 16384
    # i%64 = i & 63 (power of 2)
    # *512 = <<9
    # -16384 = - 0x4000
    input_gen_loop_start = len(code)
    emit(ANDI(t0, s2, 63), "t0 = i & 63")
    emit(SLLI(t0, t0, 9), "t0 = (i&63) * 512")
    emit_list(load_imm(s10, 16384), "s10 = 16384")
    emit(SUB(t0, t0, s10), "t0 = sample value")
    emit(SH(t0, t2, 0), "store input[i]")
    emit(ADDI(t2, t2, 2), "input ptr++")
    emit(ADDI(s2, s2, 1), "i++")
    input_gen_loop_end = len(code)
    branch_offset = (input_gen_loop_start - input_gen_loop_end) * 4
    emit(BNE(s2, s1, branch_offset & 0x1FFF), f"if i != N goto input_gen_loop ({branch_offset})")
    
    # ── Ana FIR hesaplama döngüsü ──
    # output base = 0x8000_6000
    output_base_offset = 0x6000
    emit_list(load_imm(s2, 0), "s2 = i = 0 (outer loop)")
    emit_list(load_imm(a2, output_base_offset), "a2 = output base offset")
    emit(ADD(a2, a2, s0), "a2 = output base absolute")
    emit_list(load_imm(a3, input_base_offset), "a3 = input base offset") 
    emit(ADD(a3, a3, s0), "a3 = input base absolute")
    emit_list(load_imm(a4, coef_base_offset), "a4 = coef base offset")
    emit(ADD(a4, a4, s0), "a4 = coef base absolute")
    emit_list(load_imm(a5, NUM_TAPS), "a5 = NUM_TAPS = 11")
    
    # ── OUTER LOOP: for i = 0..N-1 ──
    outer_loop_start = len(code)
    emit(ADDI(s4, x0, 0), "acc = 0")
    emit(ADDI(s3, x0, 0), "k = 0 (inner loop)")
    
    # ── INNER LOOP: for k = 0..10 ──
    inner_loop_start = len(code)
    
    # if (i - k) < 0 → skip
    emit(SUB(t0, s2, s3), "t0 = i - k")
    emit(SLTI(t1, t0, 0), "t1 = (i-k < 0) ? 1 : 0")
    # BNE t1, x0 → skip to inner_end (6 instructions ahead for multiply + acc)
    # We need to know the skip target. Let's compute offset later.
    skip_branch_idx = len(code)
    emit(NOP(), "PLACEHOLDER: BNE t1, x0, skip_mul")
    
    # Load input[i-k]
    emit(SLLI(t0, t0, 1), "t0 = (i-k) * 2 (halfword offset)")  
    emit(ADD(t0, t0, a3), "t0 = &input[i-k]")
    emit(LH(s7, t0, 0), "s7 = input[i-k] (signed 16-bit)")
    
    # Load coef[k]
    emit(SLLI(t0, s3, 1), "t0 = k * 2")
    emit(ADD(t0, t0, a4), "t0 = &coef[k]")
    emit(LH(s8, t0, 0), "s8 = coef[k] (signed 16-bit)")
    
    # Software multiply: s9 = s7 * s8 (signed 16-bit × 16-bit → 32-bit)
    # Shift-and-add algorithm
    # Since our values are 16-bit, we work with 32-bit intermediate
    # a = s7 (multiplicand), b = s8 (multiplier)
    # result = 0
    # Handle signs: if b < 0, negate both
    emit(ADD(a0, s7, x0), "a0 = multiplicand (input sample)")
    emit(ADD(a1, s8, x0), "a1 = multiplier (coef)")
    
    # Inline multiply — Booth-like:
    # We use absolute values and track sign
    emit(SRAI(t0, a1, 31), "t0 = sign_mask of multiplier")
    emit(XOR(a1, a1, t0), "abs step 1")
    emit(SUB(a1, a1, t0), "a1 = abs(multiplier)")
    emit(SRAI(t1, a0, 31), "t1 = sign_mask of multiplicand")
    emit(XOR(a0, a0, t1), "abs step 1")
    emit(SUB(a0, a0, t1), "a0 = abs(multiplicand)")
    emit(XOR(s10, t0, t1), "s10 = result sign mask (XOR of both)")
    
    emit(ADDI(s9, x0, 0), "s9 = product = 0")
    emit(ADDI(s11, x0, 16), "s11 = 16 (bit count)")
    
    # multiply loop (16 iterations — unroll would be too large)
    mul_loop_start = len(code)
    emit(ANDI(t0, a1, 1), "t0 = multiplier LSB")
    mul_skip_idx = len(code)
    emit(NOP(), "PLACEHOLDER: BEQ t0, x0, skip_add")
    emit(ADD(s9, s9, a0), "product += multiplicand (if bit set)")
    mul_skip_target = len(code)
    emit(SLLI(a0, a0, 1), "multiplicand <<= 1")
    emit(SRLI(a1, a1, 1), "multiplier >>= 1")
    emit(ADDI(s11, s11, -1), "bit_count--")
    mul_loop_end = len(code)
    mul_branch_offset = (mul_loop_start - mul_loop_end) * 4
    emit(BNE(s11, x0, mul_branch_offset & 0x1FFF), f"if bit_count != 0 goto mul_loop ({mul_branch_offset})")
    
    # Fix skip_add branch
    mul_skip_offset = (mul_skip_target - mul_skip_idx) * 4
    code[mul_skip_idx] = BEQ(t0, x0, mul_skip_offset & 0x1FFF)
    comments[mul_skip_idx] = f"if bit==0 skip add ({mul_skip_offset})"
    
    # Apply sign
    emit(XOR(s9, s9, s10), "apply sign step 1")
    emit(SUB(s9, s9, s10), "s9 = signed product")
    
    # Accumulate
    emit(ADD(s4, s4, s9), "acc += input[i-k] * coef[k]")
    
    # ── (skip_mul target is here) ──
    inner_skip_target = len(code)
    
    # Fix skip branch
    skip_offset = (inner_skip_target - skip_branch_idx) * 4
    code[skip_branch_idx] = BNE(t1, x0, skip_offset & 0x1FFF)
    comments[skip_branch_idx] = f"if (i-k)<0 skip multiply ({skip_offset})"
    
    # k++
    emit(ADDI(s3, s3, 1), "k++")
    inner_loop_end = len(code)
    inner_branch_offset = (inner_loop_start - inner_loop_end) * 4
    emit(BNE(s3, a5, inner_branch_offset & 0x1FFF), f"if k != 11 goto inner_loop ({inner_branch_offset})")
    
    # ── Store output[i] = acc >> 16 (Q31 → Q15 normalizasyon) ──
    emit(SRAI(s4, s4, 16), "output = acc >> 16")
    emit(SW(s4, a2, 0), "store output[i]")
    emit(ADDI(a2, a2, 4), "output ptr += 4")
    
    # İlk ve son çıkışı kaydet
    # if i == 0: t5 = output
    emit(BNE(s2, x0, 8), "if i != 0, skip first capture")
    emit(ADD(t5, s4, x0), "t5 = first output")
    
    # i++
    emit(ADDI(s2, s2, 1), "i++")
    outer_loop_end = len(code)
    outer_branch_offset = (outer_loop_start - outer_loop_end) * 4
    emit(BNE(s2, s1, outer_branch_offset & 0x1FFF), f"if i != N goto outer_loop ({outer_branch_offset})")
    
    # Son çıkışı kaydet
    emit(ADD(t6, s4, x0), "t6 = last output")
    
    # Sonuçları register'lara yaz
    emit_list(load_imm(t3, N), "t3 = N (sample count)")
    emit(ADDI(t4, x0, 0), "t4 = 0 (CPU-only test)")
    
    # HALT: jal x0, 0
    emit(JAL(x0, 0), "HALT: infinite loop")
    
    return code, comments


# ═══════════════════════════════════════════════════════════════
# DSP-accelerated FIR Test Programı
# ═══════════════════════════════════════════════════════════════
def gen_dsp_fir(N):
    """
    DSP-accelerated FIR filtre testi.
    Giriş verileri AXI üzerinden DSP'ye gönderilir,
    DSP donanımı filtrelemeyi yapar.
    
    DSP Register Map (base = 0x4000_1000):
      CTRL     (0x00): [0] enable, [1] soft_reset, [2] start
      STATUS   (0x04): [0] busy, [1] out_valid
      DATA_IN  (0x08): [15:0] input data (yazıldığında validIn pulse)
      DATA_OUT_L(0x0C): [31:0] output lower 32 bits
      DATA_OUT_H(0x10): [0] output bit 32
      
    Algoritma:
      1. DSP enable (CTRL[0] = 1)
      2. For each sample i = 0..N-1:
         a. Write input[i] to DATA_IN → validIn pulse
         b. Poll STATUS[1] (out_valid)
         c. Read DATA_OUT_L (this also clears out_valid)
         d. Store result
      3. Halt
    """
    
    code = []
    comments = []
    
    def emit(instr, comment=""):
        code.append(instr)
        comments.append(comment)
    
    def emit_list(instrs, comment=""):
        for i, inst in enumerate(instrs):
            code.append(inst)
            comments.append(comment if i == 0 else "")
    
    # Register allocation:
    # s0 (x8)  = iç DMEM base (0x8000_0000)
    # s1 (x9)  = N
    # s2 (x18) = loop counter i
    # s3 (x19) = DSP base (0x4000_1000)
    # s4 (x20) = temp: input sample
    # s5 (x21) = temp: status
    # s6 (x22) = temp: output
    # s7 (x23) = output ptr
    # t0-t2    = temp
    # t3 (x28) = N (output)
    # t4 (x29) = test_type = 1
    # t5 (x30) = first output
    # t6 (x31) = last output
    
    # ── DMEM base ve giriş verisi üretimi ──
    emit_list(load_imm(s0, 0x80000000), "s0 = iç DMEM base")
    emit_list(load_imm(s1, N), "s1 = N")
    
    # Giriş verisi üretimi (iç DMEM'e — aynı sawtooth)
    input_base_offset = 0x4000
    emit_list(load_imm(s2, 0), "s2 = i = 0 (giriş üretimi)")
    emit_list(load_imm(t2, input_base_offset), "t2 = input base offset")
    emit(ADD(t2, t2, s0), "t2 = input base absolute addr")
    emit_list(load_imm(s10, 16384), "s10 = 16384")
    
    input_gen_loop_start = len(code)
    emit(ANDI(t0, s2, 63), "t0 = i & 63")
    emit(SLLI(t0, t0, 9), "t0 = (i&63) * 512")
    emit(SUB(t0, t0, s10), "t0 = sample value")
    emit(SH(t0, t2, 0), "store input[i]")
    emit(ADDI(t2, t2, 2), "input ptr++")
    emit(ADDI(s2, s2, 1), "i++")
    input_gen_loop_end = len(code)
    branch_offset = (input_gen_loop_start - input_gen_loop_end) * 4
    emit(BNE(s2, s1, branch_offset & 0x1FFF), f"if i != N goto gen_loop ({branch_offset})")
    
    # ── DSP yapılandırma ──
    emit_list(load_imm(s3, 0x40001000), "s3 = DSP base = 0x4000_1000")
    
    # DSP enable: CTRL[0] = 1
    emit(ADDI(t0, x0, 1), "t0 = 1 (enable)")
    emit(SW(t0, s3, 0x00), "DSP CTRL = 0x01 (enable)")
    
    # Birkaç NOP DSP'nin enable olması için
    emit(NOP(), "wait for enable")
    emit(NOP(), "wait")
    
    # ── DSP FIR ana döngüsü ──
    emit_list(load_imm(s2, 0), "s2 = i = 0 (DSP loop)")
    emit_list(load_imm(t2, input_base_offset), "t2 = input base offset")
    emit(ADD(t2, t2, s0), "t2 = input base addr")
    
    output_base_offset = 0x6000
    emit_list(load_imm(s7, output_base_offset), "s7 = output base offset")
    emit(ADD(s7, s7, s0), "s7 = output base addr")
    
    # DSP output pipeline dolana kadar ilk ~11 sonuç gecikmeli gelir.
    # Her sample yazıldığında validIn pulse üretilir.
    # Pipeline dolduktan sonra her yazma→valid döngüsünde 1 sonuç çıkar.
    
    dsp_loop_start = len(code)
    
    # Load input[i] from DMEM
    emit(LH(s4, t2, 0), "s4 = input[i]")
    
    # Write to DSP DATA_IN (bu yazma validIn pulse üretir)
    emit(SW(s4, s3, 0x08), "DSP DATA_IN = input[i]")
    
    # Poll STATUS[1] (out_valid) — DSP pipeline dolduktan sonra
    # ilk 10 sample'da out_valid gelmeyebilir, o durumda timeout ile devam
    
    # Basit polling: max 32 cycle bekle
    emit_list(load_imm(s5, 0), "s5 = poll counter")
    emit_list(load_imm(s11, 32), "s11 = max poll count")
    
    poll_loop_start = len(code)
    emit(LW(s6, s3, 0x04), "s6 = DSP STATUS")
    emit(ANDI(s6, s6, 2), "s6 = STATUS[1] (out_valid)")
    poll_valid_idx = len(code)
    emit(NOP(), "PLACEHOLDER: BNE s6, x0, poll_done")
    emit(ADDI(s5, s5, 1), "poll_count++")
    poll_timeout_idx = len(code)
    emit(NOP(), "PLACEHOLDER: BEQ s5, s11, poll_done")
    poll_loop_end = len(code)
    poll_offset = (poll_loop_start - poll_loop_end) * 4
    emit(JAL(x0, poll_offset & 0x1FFFFF), f"goto poll_loop ({poll_offset})")
    
    poll_done = len(code)
    # Fix poll branches
    code[poll_valid_idx] = BNE(s6, x0, (poll_done - poll_valid_idx) * 4 & 0x1FFF)
    comments[poll_valid_idx] = "if out_valid, goto poll_done"
    code[poll_timeout_idx] = BEQ(s5, s11, (poll_done - poll_timeout_idx) * 4 & 0x1FFF)
    comments[poll_timeout_idx] = "if timeout, goto poll_done"
    
    # Read output — out_valid varsa oku
    # s6 tekrar oku (out_valid check)
    emit(LW(s6, s3, 0x04), "re-read STATUS")
    emit(ANDI(s6, s6, 2), "check out_valid")
    no_read_idx = len(code)
    emit(NOP(), "PLACEHOLDER: BEQ s6, x0, skip_read")
    
    # Read DATA_OUT_L (bu okuma out_valid'i temizler)
    emit(LW(s6, s3, 0x0C), "s6 = DSP DATA_OUT_L")
    # Normalize: Q31 → Q15 (>> 16)
    emit(SRAI(s6, s6, 16), "output = dataOut >> 16")
    emit(SW(s6, s7, 0), "store output")
    emit(ADDI(s7, s7, 4), "output ptr++")
    
    # First output capture 
    emit(BNE(s2, x0, 8), "if i != 0, skip first capture")
    emit(ADD(t5, s6, x0), "t5 = first output")
    
    # Last output update
    emit(ADD(t6, s6, x0), "t6 = last output (updated each iter)")
    
    skip_read_target = len(code)
    code[no_read_idx] = BEQ(s6, x0, (skip_read_target - no_read_idx) * 4 & 0x1FFF)
    comments[no_read_idx] = "if no valid output, skip read"
    
    # i++
    emit(ADDI(s2, s2, 1), "i++")
    emit(ADDI(t2, t2, 2), "input ptr++")
    dsp_loop_end = len(code)
    dsp_branch_offset = (dsp_loop_start - dsp_loop_end) * 4
    emit(BNE(s2, s1, dsp_branch_offset & 0x1FFF), f"if i != N goto dsp_loop ({dsp_branch_offset})")
    
    # ── Pipeline drain: kalan sonuçları oku ──
    # DSP pipeline 11 aşamalı, son sample'dan sonra ~11 sonuç daha gelebilir
    emit_list(load_imm(s5, 0), "s5 = drain counter")
    emit_list(load_imm(s11, 20), "s11 = max drain cycles")
    
    drain_loop_start = len(code)
    emit(LW(s6, s3, 0x04), "STATUS oku")
    emit(ANDI(s6, s6, 2), "out_valid check")
    drain_skip_idx = len(code)
    emit(NOP(), "PLACEHOLDER: BEQ skip")
    
    emit(LW(s6, s3, 0x0C), "DATA_OUT_L oku")
    emit(SRAI(s6, s6, 16), "normalize")
    emit(ADD(t6, s6, x0), "t6 = son output güncelle")
    
    drain_skip_target = len(code)
    code[drain_skip_idx] = BEQ(s6, x0, (drain_skip_target - drain_skip_idx) * 4 & 0x1FFF)
    comments[drain_skip_idx] = "if no valid, skip"
    
    emit(ADDI(s5, s5, 1), "drain counter++")
    drain_loop_end = len(code)
    drain_offset = (drain_loop_start - drain_loop_end) * 4
    emit(BNE(s5, s11, drain_offset & 0x1FFF), f"if drain_count < 20 goto drain")
    
    # Sonuçları register'lara yaz
    emit_list(load_imm(t3, N), "t3 = N (sample count)")
    emit(ADDI(t4, x0, 1), "t4 = 1 (DSP-accelerated test)")
    
    # HALT
    emit(JAL(x0, 0), "HALT: infinite loop")
    
    return code, comments


# ═══════════════════════════════════════════════════════════════
# V2: CPU Sıralı Test — FIR Filtreleme + Veri Kopyalama (Sıralı)
# Amdahl's Law analizi için: FIR ve Copy ayrı fazlarda ölçülür.
# ═══════════════════════════════════════════════════════════════
def gen_cpu_sequential_v2(N):
    """
    CPU Sıralı Test (v2): Önce FIR filtre, sonra N-word data kopyalama.
    Phase marker'lar (x1 register'ına yazma — testbench algılar):
      x1=1 → Faz 1 başladı (FIR hesaplama)
      x1=2 → Faz 2 başladı (Veri kopyalama)
      x1=3 → Tüm işlemler tamamlandı

    Bellek düzeni:
      Katsayılar   : base + 0x2000  (11 × 2B = 22B)
      FIR giriş    : base + 0x4000  (N × 2B halfword)
      FIR çıkış    : base + 0x6000  (N × 4B word)
      Kopya kaynak  : base + 0x10000 (N × 4B word)
      Kopya hedef   : base + 0x18000 (N × 4B word)
    """
    code = []
    comments = []

    def emit(instr, comment=""):
        code.append(instr)
        comments.append(comment)

    def emit_list(instrs, comment=""):
        for i, inst in enumerate(instrs):
            code.append(inst)
            comments.append(comment if i == 0 else "")

    # ═══ BAŞLANGIÇ: Katsayıları yükle ═══
    emit_list(load_imm(s0, 0x80000000), "s0 = DMEM base")

    coef_base_offset = 0x2000
    for idx, coef in enumerate(FIR_COEFS_16):
        emit_list(load_imm(t0, coef & 0xFFFF), f"coef[{idx}] = {coef}")
        emit(SH(t0, s0, coef_base_offset + idx * 2), f"store coef[{idx}]")

    # ═══ BAŞLANGIÇ: Giriş verisi + Kopya kaynak verisi üret ═══
    input_base_offset = 0x4000
    emit_list(load_imm(s1, N), "s1 = N")
    emit_list(load_imm(s2, 0), "s2 = i = 0 (init)")
    emit_list(load_imm(t2, input_base_offset), "input offset")
    emit(ADD(t2, t2, s0), "t2 = input_ptr")
    emit_list(load_imm(a6, 0x10000), "copy_src offset")
    emit(ADD(a6, a6, s0), "a6 = copy_src_ptr")
    emit_list(load_imm(s10, 16384), "s10 = 16384 (sawtooth)")

    init_loop_start = len(code)
    emit(ANDI(t0, s2, 63), "t0 = i & 63")
    emit(SLLI(t0, t0, 9), "t0 *= 512")
    emit(SUB(t0, t0, s10), "t0 = sawtooth sample")
    emit(SH(t0, t2, 0), "store FIR input[i]")
    emit(SW(t0, a6, 0), "store copy_src[i]")
    emit(ADDI(t2, t2, 2), "input_ptr += 2")
    emit(ADDI(a6, a6, 4), "copy_src_ptr += 4")
    emit(ADDI(s2, s2, 1), "i++")
    init_loop_end = len(code)
    emit(BNE(s2, s1, (init_loop_start - init_loop_end) * 4 & 0x1FFF), "init loop")

    # ═══════════════════════════════════════════════
    # MARKER 1 — Faz 1: FIR hesaplama başlangıcı
    # ═══════════════════════════════════════════════
    emit(ADDI(x1, x0, 1), "══ MARKER_1: FIR hesaplama baslangici ══")

    # FIR outer/inner loop — aynı algoritma (shift-and-add multiply)
    output_base_offset = 0x6000
    emit_list(load_imm(s2, 0), "s2 = i = 0 (outer)")
    emit_list(load_imm(a2, output_base_offset), "output offset")
    emit(ADD(a2, a2, s0), "a2 = output_ptr")
    emit_list(load_imm(a3, input_base_offset), "input offset")
    emit(ADD(a3, a3, s0), "a3 = input_base")
    emit_list(load_imm(a4, coef_base_offset), "coef offset")
    emit(ADD(a4, a4, s0), "a4 = coef_base")
    emit_list(load_imm(a5, NUM_TAPS), "a5 = 11")

    outer_loop_start = len(code)
    emit(ADDI(s4, x0, 0), "acc = 0")
    emit(ADDI(s3, x0, 0), "k = 0")

    inner_loop_start = len(code)
    emit(SUB(t0, s2, s3), "t0 = i - k")
    emit(SLTI(t1, t0, 0), "t1 = (i-k < 0)?")
    skip_branch_idx = len(code)
    emit(NOP(), "PLACEHOLDER: skip_mul")

    emit(SLLI(t0, t0, 1), "(i-k)*2")
    emit(ADD(t0, t0, a3), "&input[i-k]")
    emit(LH(s7, t0, 0), "s7 = input[i-k]")
    emit(SLLI(t0, s3, 1), "k*2")
    emit(ADD(t0, t0, a4), "&coef[k]")
    emit(LH(s8, t0, 0), "s8 = coef[k]")

    # Shift-and-add multiply
    emit(ADD(a0, s7, x0), "a0 = multiplicand")
    emit(ADD(a1, s8, x0), "a1 = multiplier")
    emit(SRAI(t0, a1, 31), "sign(multiplier)")
    emit(XOR(a1, a1, t0), "abs step1")
    emit(SUB(a1, a1, t0), "a1 = |multiplier|")
    emit(SRAI(t1, a0, 31), "sign(multiplicand)")
    emit(XOR(a0, a0, t1), "abs step1")
    emit(SUB(a0, a0, t1), "a0 = |multiplicand|")
    emit(XOR(s10, t0, t1), "s10 = result sign")
    emit(ADDI(s9, x0, 0), "product = 0")
    emit(ADDI(s11, x0, 16), "bit_count = 16")

    mul_loop_start = len(code)
    emit(ANDI(t0, a1, 1), "LSB")
    mul_skip_idx = len(code)
    emit(NOP(), "PLACEHOLDER: skip_add")
    emit(ADD(s9, s9, a0), "product += multiplicand")
    mul_skip_target = len(code)
    emit(SLLI(a0, a0, 1), "multiplicand <<= 1")
    emit(SRLI(a1, a1, 1), "multiplier >>= 1")
    emit(ADDI(s11, s11, -1), "bit_count--")
    mul_loop_end = len(code)
    emit(BNE(s11, x0, (mul_loop_start - mul_loop_end) * 4 & 0x1FFF), "mul loop")

    code[mul_skip_idx] = BEQ(t0, x0, (mul_skip_target - mul_skip_idx) * 4 & 0x1FFF)
    comments[mul_skip_idx] = "if bit==0 skip add"

    emit(XOR(s9, s9, s10), "sign step1")
    emit(SUB(s9, s9, s10), "signed product")
    emit(ADD(s4, s4, s9), "acc += sample*coef")

    inner_skip_target = len(code)
    code[skip_branch_idx] = BNE(t1, x0, (inner_skip_target - skip_branch_idx) * 4 & 0x1FFF)
    comments[skip_branch_idx] = "if (i-k)<0 skip mul"

    emit(ADDI(s3, s3, 1), "k++")
    inner_loop_end = len(code)
    emit(BNE(s3, a5, (inner_loop_start - inner_loop_end) * 4 & 0x1FFF), "inner loop")

    emit(SRAI(s4, s4, 16), "output = acc >> 16")
    emit(SW(s4, a2, 0), "store output[i]")
    emit(ADDI(a2, a2, 4), "output_ptr++")

    emit(BNE(s2, x0, 8), "skip first capture")
    emit(ADD(t5, s4, x0), "t5 = first output")

    emit(ADDI(s2, s2, 1), "i++")
    outer_loop_end = len(code)
    emit(BNE(s2, s1, (outer_loop_start - outer_loop_end) * 4 & 0x1FFF), "outer loop")

    emit(ADD(t6, s4, x0), "t6 = last output")

    # ═══════════════════════════════════════════════
    # MARKER 2 — Faz 2: Veri kopyalama başlangıcı
    # ═══════════════════════════════════════════════
    emit(ADDI(x1, x0, 2), "══ MARKER_2: Kopyalama baslangici ══")

    emit_list(load_imm(s2, 0), "s2 = i = 0 (copy)")
    emit_list(load_imm(a6, 0x10000), "copy_src offset")
    emit(ADD(a6, a6, s0), "a6 = copy_src_ptr")
    emit_list(load_imm(a7, 0x18000), "copy_dst offset")
    emit(ADD(a7, a7, s0), "a7 = copy_dst_ptr")

    copy_loop_start = len(code)
    emit(LW(t0, a6, 0), "t0 = copy_src[i]")
    emit(SW(t0, a7, 0), "copy_dst[i] = t0")
    emit(ADDI(a6, a6, 4), "src++")
    emit(ADDI(a7, a7, 4), "dst++")
    emit(ADDI(s2, s2, 1), "i++")
    copy_loop_end = len(code)
    emit(BNE(s2, s1, (copy_loop_start - copy_loop_end) * 4 & 0x1FFF), "copy loop")

    # ═══════════════════════════════════════════════
    # MARKER 3 — Tüm işlemler tamamlandı
    # ═══════════════════════════════════════════════
    emit(ADDI(x1, x0, 3), "══ MARKER_3: Tamamlandi ══")

    emit_list(load_imm(t3, N), "t3 = N")
    emit(ADDI(t4, x0, 0), "t4 = 0 (CPU sequential)")
    emit(JAL(x0, 0), "HALT")

    return code, comments


# ═══════════════════════════════════════════════════════════════
# V2: DSP Paralel Test — DSP FIR + CPU Copy (İnterleaved/Paralel)
# Core DSP'ye sample gönderirken aynı anda kopyalama işi yapar.
# ═══════════════════════════════════════════════════════════════
def gen_dsp_parallel_v2(N):
    """
    DSP Paralel Test (v2): DSP'ye sample gönder + CPU kopyalama eşzamanlı.
    Phase marker'lar:
      x1=1 → Faz 1 başladı (DSP + Copy interleaved)
      x1=2 → Faz 2 başladı (DSP pipeline drain)
      x1=3 → Tüm işlemler tamamlandı

    Her iterasyonda:
      1. CPU → DSP DATA_IN yazma (AXI write)
      2. CPU → 1 word kopyalama (DMEM internal, DSP pipeline çalışırken)
      3. CPU → DSP STATUS okuma (AXI read)
      4. Eğer out_valid → DSP DATA_OUT_L okuma + store
    """
    code = []
    comments = []

    def emit(instr, comment=""):
        code.append(instr)
        comments.append(comment)

    def emit_list(instrs, comment=""):
        for i, inst in enumerate(instrs):
            code.append(inst)
            comments.append(comment if i == 0 else "")

    # ═══ BAŞLANGIÇ: Giriş verisi + Kopya kaynak verisi üret ═══
    input_base_offset = 0x4000
    emit_list(load_imm(s0, 0x80000000), "s0 = DMEM base")
    emit_list(load_imm(s1, N), "s1 = N")
    emit_list(load_imm(s2, 0), "s2 = i = 0 (init)")
    emit_list(load_imm(t2, input_base_offset), "input offset")
    emit(ADD(t2, t2, s0), "t2 = input_ptr")
    emit_list(load_imm(a6, 0x10000), "copy_src offset")
    emit(ADD(a6, a6, s0), "a6 = copy_src_ptr")
    emit_list(load_imm(s10, 16384), "s10 = 16384")

    init_loop_start = len(code)
    emit(ANDI(t0, s2, 63), "t0 = i & 63")
    emit(SLLI(t0, t0, 9), "t0 *= 512")
    emit(SUB(t0, t0, s10), "t0 = sawtooth sample")
    emit(SH(t0, t2, 0), "store FIR input[i]")
    emit(SW(t0, a6, 0), "store copy_src[i]")
    emit(ADDI(t2, t2, 2), "input_ptr += 2")
    emit(ADDI(a6, a6, 4), "copy_src_ptr += 4")
    emit(ADDI(s2, s2, 1), "i++")
    init_loop_end = len(code)
    emit(BNE(s2, s1, (init_loop_start - init_loop_end) * 4 & 0x1FFF), "init loop")

    # DSP enable
    emit_list(load_imm(s3, 0x40001000), "s3 = DSP base")
    emit(ADDI(t0, x0, 1), "enable bit")
    emit(SW(t0, s3, 0x00), "DSP CTRL = enable")
    emit(NOP(), "wait")
    emit(NOP(), "wait")

    # ═══════════════════════════════════════════════
    # MARKER 1 — Faz 1: DSP + Copy paralel başlangıcı
    # ═══════════════════════════════════════════════
    emit(ADDI(x1, x0, 1), "══ MARKER_1: DSP+Copy paralel baslangici ══")

    # Pointer setup
    emit_list(load_imm(s2, 0), "s2 = i = 0 (main loop)")
    emit_list(load_imm(t2, input_base_offset), "input offset")
    emit(ADD(t2, t2, s0), "t2 = input_ptr")
    output_base_offset = 0x6000
    emit_list(load_imm(s7, output_base_offset), "output offset")
    emit(ADD(s7, s7, s0), "s7 = fir_output_ptr")
    emit_list(load_imm(s8, 0x10000), "copy_src offset")
    emit(ADD(s8, s8, s0), "s8 = copy_src_ptr")
    emit_list(load_imm(s9, 0x18000), "copy_dst offset")
    emit(ADD(s9, s9, s0), "s9 = copy_dst_ptr")

    # ═══ İnterleaved ana döngü ═══
    dsp_loop_start = len(code)

    # 1) DSP'ye sample gönder
    emit(LH(s4, t2, 0), "s4 = input[i]")
    emit(SW(s4, s3, 0x08), "DSP DATA_IN = input[i]")

    # 2) Kopyalama (DSP pipeline çalışırken)
    emit(LW(s10, s8, 0), "copy: load src[i]")
    emit(SW(s10, s9, 0), "copy: store dst[i]")
    emit(ADDI(s8, s8, 4), "copy_src++")
    emit(ADDI(s9, s9, 4), "copy_dst++")

    # 3) DSP STATUS kontrol
    emit(LW(s5, s3, 0x04), "DSP STATUS")
    emit(ANDI(s5, s5, 2), "out_valid?")
    no_read_idx = len(code)
    emit(NOP(), "PLACEHOLDER: skip_read")

    # 4) DSP çıkışı oku + depola
    emit(LW(s6, s3, 0x0C), "DATA_OUT_L")
    emit(SRAI(s6, s6, 16), "normalize >> 16")
    emit(SW(s6, s7, 0), "store fir_output")
    emit(ADDI(s7, s7, 4), "output_ptr++")

    # İlk/son output yakala
    emit(BNE(s2, x0, 8), "skip first capture")
    emit(ADD(t5, s6, x0), "t5 = first output")
    emit(ADD(t6, s6, x0), "t6 = last output")

    skip_read_target = len(code)
    code[no_read_idx] = BEQ(s5, x0, (skip_read_target - no_read_idx) * 4 & 0x1FFF)
    comments[no_read_idx] = "if no valid, skip read"

    # i++ ve pointer ilerlet
    emit(ADDI(s2, s2, 1), "i++")
    emit(ADDI(t2, t2, 2), "input_ptr++")
    dsp_loop_end = len(code)
    emit(BNE(s2, s1, (dsp_loop_start - dsp_loop_end) * 4 & 0x1FFF), "main loop")

    # ═══════════════════════════════════════════════
    # MARKER 2 — Faz 2: DSP pipeline drain
    # ═══════════════════════════════════════════════
    emit(ADDI(x1, x0, 2), "══ MARKER_2: DSP drain baslangici ══")

    emit_list(load_imm(s5, 0), "drain counter")
    emit_list(load_imm(s11, 20), "max drain")

    drain_start = len(code)
    emit(LW(s6, s3, 0x04), "STATUS")
    emit(ANDI(s6, s6, 2), "out_valid?")
    drain_skip_idx = len(code)
    emit(NOP(), "PLACEHOLDER: drain skip")

    emit(LW(s6, s3, 0x0C), "DATA_OUT_L")
    emit(SRAI(s6, s6, 16), "normalize")
    emit(SW(s6, s7, 0), "store output")
    emit(ADDI(s7, s7, 4), "output_ptr++")
    emit(ADD(t6, s6, x0), "t6 = last output")

    drain_skip_target = len(code)
    code[drain_skip_idx] = BEQ(s6, x0, (drain_skip_target - drain_skip_idx) * 4 & 0x1FFF)
    comments[drain_skip_idx] = "skip if no valid"

    emit(ADDI(s5, s5, 1), "drain++")
    drain_end = len(code)
    emit(BNE(s5, s11, (drain_start - drain_end) * 4 & 0x1FFF), "drain loop")

    # ═══════════════════════════════════════════════
    # MARKER 3 — Tüm işlemler tamamlandı
    # ═══════════════════════════════════════════════
    emit(ADDI(x1, x0, 3), "══ MARKER_3: Tamamlandi ══")

    emit_list(load_imm(t3, N), "t3 = N")
    emit(ADDI(t4, x0, 1), "t4 = 1 (DSP parallel)")
    emit(JAL(x0, 0), "HALT")

    return code, comments


def write_mem_file(filepath, code, comments, header_lines=None):
    """Write .mem file with hex instructions and comments"""
    with open(filepath, 'w', encoding='utf-8') as f:
        if header_lines:
            for line in header_lines:
                f.write(f"// {line}\n")
            f.write("\n")
        
        for i, (instr, comment) in enumerate(zip(code, comments)):
            hex_str = _to_hex(instr)
            addr = 0x80000000 + i * 4
            if comment:
                f.write(f"{hex_str}  // {addr:#010x}: {comment}\n")
            else:
                f.write(f"{hex_str}\n")


def main():
    # Çıktı dizini
    out_dir = os.path.dirname(os.path.abspath(__file__))
    # mem dosyalarını sim/ ve tb/ klasörlerine koy
    sim_dir = os.path.join(os.path.dirname(out_dir), '..', 'sim')  
    tb_dir = out_dir  # tb/soc_tb/
    
    # Normalize paths
    sim_dir = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'sim'))
    tb_dir = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

    print("=" * 70)
    print("  DSP Performans Testi — .mem Dosya Üreteci")
    print("=" * 70)
    print(f"  Sim dir: {sim_dir}")
    print(f"  TB dir:  {tb_dir}")
    print(f"  Sample sizes: {SAMPLE_SIZES}")
    print(f"  FIR taps: {NUM_TAPS}")
    print(f"  FIR coeffs: {FIR_COEFS_16}")
    print()
    
    for N in SAMPLE_SIZES:
        # ── CPU-only test ──
        cpu_code, cpu_comments = gen_cpu_only_fir(N)
        cpu_filename = f"imem_perf_cpu_{N}.mem"
        
        header = [
            f"imem_perf_cpu_{N}.mem — CPU-only FIR Filter Test (N={N})",
            f"11-TAP Hamming FIR, shift-and-add software multiply",
            f"Test type: CPU-only (t4=0), Sample count: {N} (t3={N})",
            f"Generated by gen_dsp_perf_tests.py",
            f"Instruction count: {len(cpu_code)}",
        ]
        
        # tb/ ve sim/ klasörlerine yaz
        for d in [tb_dir, sim_dir]:
            filepath = os.path.join(d, cpu_filename)
            write_mem_file(filepath, cpu_code, cpu_comments, header)
        
        print(f"  [CPU ] N={N:5d} → {cpu_filename} ({len(cpu_code)} instructions)")
        
        # ── DSP-accelerated test ──
        dsp_code, dsp_comments = gen_dsp_fir(N)
        dsp_filename = f"imem_perf_dsp_{N}.mem"
        
        header = [
            f"imem_perf_dsp_{N}.mem — DSP-accelerated FIR Filter Test (N={N})",
            f"11-TAP Hamming FIR via hardware DSP (AXI4-Lite)",
            f"Test type: DSP-accelerated (t4=1), Sample count: {N} (t3={N})",
            f"Generated by gen_dsp_perf_tests.py",
            f"Instruction count: {len(dsp_code)}",
        ]
        
        for d in [tb_dir, sim_dir]:
            filepath = os.path.join(d, dsp_filename)
            write_mem_file(filepath, dsp_code, dsp_comments, header)
        
        print(f"  [DSP ] N={N:5d} → {dsp_filename} ({len(dsp_code)} instructions)")
    
    print()
    print(f"  Toplam: {len(SAMPLE_SIZES) * 2} v1 mem dosyasi uretildi.")
    print()

    # ═══ V2 Test Dosyaları (Amdahl's Law — FIR + Copy) ═══
    print("  ── V2 Testler (FIR + Copy) ──")
    for N in SAMPLE_SIZES:
        # CPU sequential v2
        cpu_code, cpu_comments = gen_cpu_sequential_v2(N)
        cpu_filename = f"imem_perf_v2_cpu_{N}.mem"
        header = [
            f"imem_perf_v2_cpu_{N}.mem — CPU Sequential: FIR + Copy (N={N})",
            f"Faz 1: 11-TAP FIR (shift-and-add), Faz 2: N-word kopyalama",
            f"Marker: x1=1 (FIR start), x1=2 (Copy start), x1=3 (Done)",
            f"Generated by gen_dsp_perf_tests.py (v2)",
            f"Instruction count: {len(cpu_code)}",
        ]
        for d in [tb_dir, sim_dir]:
            write_mem_file(os.path.join(d, cpu_filename), cpu_code, cpu_comments, header)
        print(f"  [CPUv2] N={N:5d} -> {cpu_filename} ({len(cpu_code)} instr)")

        # DSP parallel v2
        dsp_code, dsp_comments = gen_dsp_parallel_v2(N)
        dsp_filename = f"imem_perf_v2_dsp_{N}.mem"
        header = [
            f"imem_perf_v2_dsp_{N}.mem — DSP Parallel: DSP FIR + CPU Copy (N={N})",
            f"Faz 1: DSP FIR + CPU Copy interleaved, Faz 2: DSP drain",
            f"Marker: x1=1 (Parallel start), x1=2 (Drain start), x1=3 (Done)",
            f"Generated by gen_dsp_perf_tests.py (v2)",
            f"Instruction count: {len(dsp_code)}",
        ]
        for d in [tb_dir, sim_dir]:
            write_mem_file(os.path.join(d, dsp_filename), dsp_code, dsp_comments, header)
        print(f"  [DSPv2] N={N:5d} -> {dsp_filename} ({len(dsp_code)} instr)")

    total = len(SAMPLE_SIZES) * 4
    print()
    print(f"  Toplam: {total} mem dosyasi uretildi (v1 + v2).")
    print("=" * 70)


if __name__ == "__main__":
    main()
