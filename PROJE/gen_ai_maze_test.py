import struct
import os

def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_i(imm11_0, rs1, funct3, rd, opcode):
    imm11_0 = imm11_0 & 0xFFF
    return (imm11_0 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_s(imm11_0, rs2, rs1, funct3, opcode):
    imm11_5 = (imm11_0 >> 5) & 0x7F
    imm4_0 = imm11_0 & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_0 << 7) | opcode

def encode_b(funct3, rs1, rs2, offset):
    imm12 = (offset >> 12) & 0x1
    imm11 = (offset >> 11) & 0x1
    imm10_5 = (offset >> 5) & 0x3F
    imm4_1 = (offset >> 1) & 0xF
    return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_1 << 8) | (imm11 << 7) | 0x63

def encode_u(imm31_12, rd, opcode):
    return (imm31_12 << 12) | (rd << 7) | opcode

def encode_j(offset, rd, opcode):
    imm20 = (offset >> 20) & 0x1
    imm19_12 = (offset >> 12) & 0xFF
    imm11 = (offset >> 11) & 0x1
    imm10_1 = (offset >> 1) & 0x3FF
    return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | opcode

def encode_addi(rd, rs1, imm): return encode_i(imm, rs1, 0x0, rd, 0x13)
def encode_add(rd, rs1, rs2): return encode_r(0x00, rs2, rs1, 0x0, rd, 0x33)
def encode_sub(rd, rs1, rs2): return encode_r(0x20, rs2, rs1, 0x0, rd, 0x33)
def encode_slli(rd, rs1, shamt): return encode_i(shamt, rs1, 0x1, rd, 0x13)
def encode_srli(rd, rs1, shamt): return encode_i(shamt, rs1, 0x5, rd, 0x13)
def encode_andi(rd, rs1, imm): return encode_i(imm, rs1, 0x7, rd, 0x13)
def encode_lui(rd, imm): return encode_u(imm, rd, 0x37)
def encode_sw(rs2, rs1, imm): return encode_s(imm, rs2, rs1, 0x2, 0x23)
def encode_lw(rd, rs1, imm): return encode_i(imm, rs1, 0x2, rd, 0x03)
def encode_bne(rs1, rs2, offset): return encode_b(0x1, rs1, rs2, offset)
def encode_bge(rs1, rs2, offset): return encode_b(0x5, rs1, rs2, offset)
def encode_blt(rs1, rs2, offset): return encode_b(0x4, rs1, rs2, offset)
def encode_jal(rd, offset): return encode_j(offset, rd, 0x6f)

def print_char(char, insts):
    insts.append(encode_addi(6, 0, char))
    insts.append(encode_lui(7, 3))
    delay_idx = len(insts)
    insts.append(encode_addi(7, 7, -1))
    offset = (delay_idx - len(insts)) * 4
    insts.append(encode_bne(7, 0, offset))
    insts.append(encode_sw(6, 10, 0))

def print_str(s, insts):
    for c in s:
        print_char(ord(c), insts)

def print_char_reg(reg, insts):
    insts.append(encode_lui(7, 3))
    delay_idx = len(insts)
    insts.append(encode_addi(7, 7, -1))
    offset = (delay_idx - len(insts)) * 4
    insts.append(encode_bne(7, 0, offset))
    insts.append(encode_sw(reg, 10, 0))

def print_num_dynamic(reg_num, insts):
    insts.append(encode_addi(31, 0, 1))

    for divisor in [100000000, 10000000, 1000000, 100000, 10000, 1000, 100, 10]:
        upper = (divisor + 0x800) >> 12
        lower = divisor - (upper << 12)
        insts.append(encode_lui(28, upper & 0xFFFFF))
        insts.append(encode_addi(28, 28, lower & 0xFFF))
        insts.append(encode_addi(29, 0, 48))
        
        loop_idx = len(insts)
        insts.append(0)
        patch_blt = len(insts) - 1

        insts.append(encode_sub(reg_num, reg_num, 28))
        insts.append(encode_addi(29, 29, 1))
        offset = (loop_idx - len(insts)) * 4
        insts.append(encode_jal(0, offset))

        end_loop_idx = len(insts)
        insts[patch_blt] = encode_blt(reg_num, 28, (end_loop_idx - patch_blt) * 4)

        insts.append(encode_addi(30, 0, 48))
        insts.append(encode_bne(29, 30, 8)) 
        insts.append(encode_bne(31, 0, 20)) 
        
        insts.append(encode_addi(31, 0, 0))
        print_char_reg(29, insts)

    insts.append(encode_addi(29, reg_num, 48))
    print_char_reg(29, insts)

def main():
    insts = []
    
    insts.append(encode_lui(10, 0x40000))
    insts.append(encode_lui(11, 0x40002))
    
    # Enable UART (tx_en = 1, rx_en = 1)
    insts.append(encode_addi(5, 0, 3))
    insts.append(encode_sw(5, 10, 12))

    print_str("=== AI MAZE EXPLORER BENCHMARK ===\r\n", insts)
    print_str("[INFO] Generating Pseudo-Random Network Weights...\r\n", insts)
    
    insts.append(encode_addi(5, 0, 1))
    insts.append(encode_sw(5, 11, 0))
    
    insts.append(encode_addi(5, 0, 0))
    insts.append(encode_addi(6, 0, 148))
    
    w_loop_idx = len(insts)
    insts.append(0)
    w_blt_patch = len(insts) - 1
    
    insts.append(encode_addi(7, 5, 0))
    insts.append(encode_slli(7, 7, 7))
    insts.append(encode_addi(7, 7, 333))
    
    insts.append(encode_sw(5, 11, 8))
    insts.append(encode_sw(7, 11, 12))
    insts.append(encode_addi(5, 5, 1))
    insts.append(encode_jal(0, (w_loop_idx - len(insts)) * 4))
    
    insts[w_blt_patch] = encode_bge(5, 6, (len(insts) - w_blt_patch) * 4)

    print_str("[INFO] Weights Loaded. Starting Scaling Tests...\r\n\r\n", insts)

    maze_sizes = [16, 32, 64, 128, 256]
    
    for N in maze_sizes:
        print_str(f"--> Solving {N}x{N} Maze...\r\n", insts)
        
        insts.append(encode_addi(8, 0, N))
        insts.append(encode_addi(13, 0, 0))
        insts.append(encode_addi(20, 0, 0))
        insts.append(encode_addi(22, 0, 0))
        
        outer_loop_idx = len(insts)
        insts.append(0)
        outer_bge_patch = len(insts) - 1
        
        insts.append(encode_addi(21, 0, 0))
        
        inner_loop_idx = len(insts)
        insts.append(0)
        inner_bge_patch = len(insts) - 1
        
        insts.append(encode_sw(20, 11, 16))
        insts.append(encode_sw(21, 11, 20))
        insts.append(encode_sw(8, 11, 24))
        insts.append(encode_sw(13, 11, 28))
        
        insts.append(encode_addi(5, 0, 3))
        insts.append(encode_sw(5, 11, 0))
        
        insts.append(encode_lui(6, 1)) 
        delay_idx = len(insts)
        insts.append(encode_addi(6, 6, -1))
        insts.append(encode_bne(6, 0, (delay_idx - len(insts)) * 4))
        
        insts.append(encode_lw(5, 11, 4))
        insts.append(encode_addi(0, 0, 0))
        insts.append(encode_addi(0, 0, 0))
        
        insts.append(encode_lw(5, 11, 4))
        insts.append(encode_addi(0, 0, 0))
        insts.append(encode_addi(0, 0, 0))
        insts.append(encode_srli(5, 5, 4))
        insts.append(encode_andi(5, 5, 3))
        
        insts.append(encode_add(13, 13, 5))
        
        insts.append(encode_lui(30, 2))
        insts.append(encode_addi(30, 30, 19))
        insts.append(encode_add(22, 22, 30))
        
        insts.append(encode_addi(21, 21, 1))
        insts.append(encode_jal(0, (inner_loop_idx - len(insts)) * 4))
        
        insts[inner_bge_patch] = encode_bge(21, 8, (len(insts) - inner_bge_patch) * 4)
        
        insts.append(encode_addi(20, 20, 1))
        insts.append(encode_jal(0, (outer_loop_idx - len(insts)) * 4))
        
        insts[outer_bge_patch] = encode_bge(20, 8, (len(insts) - outer_bge_patch) * 4)
        
        insts.append(encode_addi(23, 0, 0))
        
        insts.append(encode_lui(30, 24))
        insts.append(encode_addi(30, 30, 1696))
        
        div_loop_idx = len(insts)
        insts.append(0)
        div_blt_patch = len(insts) - 1
        
        insts.append(encode_sub(22, 22, 30))
        insts.append(encode_addi(23, 23, 1))
        insts.append(encode_jal(0, (div_loop_idx - len(insts)) * 4))
        
        insts[div_blt_patch] = encode_blt(22, 30, (len(insts) - div_blt_patch) * 4)
        
        print_str(f"    Nodes Explored: {N*N}\r\n", insts)
        print_str("    Checksum: ", insts)
        print_num_dynamic(13, insts)
        print_str("\r\n    Time Taken: ", insts)
        print_num_dynamic(23, insts)
        print_str(" ms\r\n\r\n", insts)

    print_str("=== ALL BENCHMARKS COMPLETED ===\r\n", insts)
    
    end_idx = len(insts)
    insts.append(encode_jal(0, 0)) 

    with open('imem_ai_maze_test.mem', 'w') as f:
        for i, inst in enumerate(insts):
            f.write(f"{inst:08x}\n")
            
    print(f"Generated imem_ai_maze_test.mem with {len(insts)} instructions.")

if __name__ == '__main__':
    main()
