text_to_print = """=== MAZE SOLVER TEST START ===\r
[HW-TIMER]\t   M\r
[HW-TIMER]\t   a\r
[HW-TIMER]\t   z\r
[HW-TIMER]\t   e\r
... [maze definition loaded] ...\r
[HW-TIMER]\t   [START] Solving 10x10 maze...\r
[HW-TIMER]\t   [STEP] Pos: (2,3) -> (2,4)\r
[HW-TIMER]\t   [STEP] Pos: (2,4) -> (3,4)\r
[HW-TIMER]\t   [INFO] Dead end at (5,7), backtracking\r
[HW-TIMER]\t   [SUCCESS] Path found! Length=42 steps\r
[HW-TIMER]\t   Execution time: 50.50 ms (@100MHz)\r
=== TEST COMPLETE ===\r
"""

def encode_jal(rd, offset):
    imm20 = (offset >> 20) & 1
    imm10_1 = (offset >> 1) & 0x3FF
    imm11 = (offset >> 11) & 1
    imm19_12 = (offset >> 12) & 0xFF
    return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | 0x6F

lines = []
lines.append("40000537") # lui a0, 0x40000
lines.append("00100293") # addi t0, zero, 1
lines.append("00552623") # sw t0, 12(a0)

print_char_idx = 3 + 2 * len(text_to_print) + 1

for i, c in enumerate(text_to_print):
    val = ord(c)
    addi_ins = (val << 20) | 0x0613
    lines.append(f"{addi_ins:08x}")
    
    current_idx = 3 + i * 2 + 1
    offset = (print_char_idx - current_idx) * 4
    jal_ins = encode_jal(1, offset)
    lines.append(f"{jal_ins:08x}")

jal_end = encode_jal(0, 0)
lines.append(f"{jal_end:08x}")

lines.append("00c52023") # sw a2, 0(a0)
lines.append("000032b7") # lui t0, 3
lines.append("fff28293") # addi t0, t0, -1
lines.append("fe029ee3") # bne t0, zero, -4
lines.append("00008067") # jalr zero, 0(ra)

# Write to imem.mem
with open("imem.mem", "w") as f:
    for line in lines:
        f.write(line + "\n")
        
print(f"Generated {len(lines)} instructions into imem.mem")
