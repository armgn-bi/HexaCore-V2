import sys

def encode_lui(rd, imm):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | 0x37

def encode_addi(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0x0 << 12) | (rd << 7) | 0x13

def encode_sw(rs2, rs1, imm):
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0 = imm & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0x2 << 12) | (imm4_0 << 7) | 0x23

def encode_lw(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0x2 << 12) | (rd << 7) | 0x03

def encode_bne(rs1, rs2, offset):
    imm12 = (offset >> 12) & 0x1
    imm11 = (offset >> 11) & 0x1
    imm10_5 = (offset >> 5) & 0x3F
    imm4_1 = (offset >> 1) & 0xF
    return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0x1 << 12) | (imm4_1 << 8) | (imm11 << 7) | 0x63

def encode_beq(rs1, rs2, offset):
    imm12 = (offset >> 12) & 0x1
    imm11 = (offset >> 11) & 0x1
    imm10_5 = (offset >> 5) & 0x3F
    imm4_1 = (offset >> 1) & 0xF
    return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0x0 << 12) | (imm4_1 << 8) | (imm11 << 7) | 0x63

def encode_srli(rd, rs1, shamt):
    return (0x00 << 25) | ((shamt & 0x1F) << 20) | (rs1 << 15) | (0x5 << 12) | (rd << 7) | 0x13

def encode_andi(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0x7 << 12) | (rd << 7) | 0x13

def print_char(char, insts):
    # Wait ~36,000 cycles to guarantee UART has transmitted the byte
    # t1 (x6) = 3 (shifted by 12 = 12288)
    insts.append(encode_lui(6, 3))
    delay_idx = len(insts)
    # addi t1, t1, -1
    insts.append(encode_addi(6, 6, -1))
    # bne t1, zero, delay_idx
    offset = (delay_idx - len(insts)) * 4
    insts.append(encode_bne(6, 0, offset))

    # Then write char to UART
    insts.append(encode_addi(5, 0, ord(char)))
    insts.append(encode_sw(5, 10, 0))

def print_str(s, insts):
    for c in s:
        print_char(c, insts)

insts = []

# a0 (x10) = 0x40000000 (UART)
insts.append(encode_lui(10, 0x40000))
# a1 (x11) = 0x40002000 (DQN)
insts.append(encode_lui(11, 0x40002))

# enable uart
insts.append(encode_addi(5, 0, 1))
insts.append(encode_sw(5, 10, 12))

print_str("=== DQN ACCELERATOR TEST ===\r\n", insts)
print_str("[INFO] Enabling Weights Mode...\r\n", insts)

insts.append(encode_addi(5, 0, 9))
insts.append(encode_sw(5, 11, 0))

print_str("[INFO] Loading 148 Weights (0.125)...\r\n", insts)

insts.append(encode_sw(0, 11, 0x2C))

insts.append(encode_addi(7, 0, 148))
insts.append(encode_addi(28, 0, 0x0400)) # Q1.15 0.125
loop_start_idx = len(insts)
insts.append(encode_sw(28, 11, 0x30))
insts.append(encode_addi(7, 7, -1))
offset = (loop_start_idx - len(insts)) * 4
insts.append(encode_bne(7, 0, offset))

print_str("[INFO] Setting States (0.5, 0.25, 0.125, 0.0)...\r\n", insts)

insts.append(encode_lui(5, 0x4))
insts.append(encode_sw(5, 11, 0x08))

insts.append(encode_lui(5, 0x2))
insts.append(encode_sw(5, 11, 0x0C))

insts.append(encode_lui(5, 0x1))
insts.append(encode_sw(5, 11, 0x10))

insts.append(encode_sw(0, 11, 0x14))

insts.append(encode_addi(5, 0, 1))
insts.append(encode_sw(5, 11, 0))

print_str("[INFO] Triggering Inference...\r\n", insts)

insts.append(encode_addi(5, 0, 3))
insts.append(encode_sw(5, 11, 0))

# Instead of polling, just wait for ~36,000 cycles (more than enough for 33 cycle inference)
insts.append(encode_lui(6, 3))
delay_idx = len(insts)
insts.append(encode_addi(6, 6, -1))
offset = (delay_idx - len(insts)) * 4
insts.append(encode_bne(6, 0, offset))

print_str("[SUCCESS] Inference Complete! Argmax: ", insts)

# Read STATUS
insts.append(encode_lw(5, 11, 4))
# NOPs to avoid load-use hazard!
insts.append(encode_addi(0, 0, 0))
insts.append(encode_addi(0, 0, 0))
insts.append(encode_addi(0, 0, 0))

# Extract argmax
insts.append(encode_srli(5, 5, 4))
insts.append(encode_andi(5, 5, 3))
insts.append(encode_addi(5, 5, 48))

# Wait for UART
insts.append(encode_lui(6, 3))
delay_idx = len(insts)
insts.append(encode_addi(6, 6, -1))
offset = (delay_idx - len(insts)) * 4
insts.append(encode_bne(6, 0, offset))

# Write the character in x5 to UART
insts.append(encode_sw(5, 10, 0))

print_str("\r\n=== TEST DONE ===\r\n", insts)

# Infinite loop
inf_idx = len(insts)
offset = (inf_idx - len(insts)) * 4
insts.append(encode_beq(0, 0, offset))

with open("imem.mem", "w") as f:
    for instr in insts:
        f.write(f"{instr:08x}\n")

print(f"Generated {len(insts)} instructions into imem.mem")
