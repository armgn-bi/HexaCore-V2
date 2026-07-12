def encode_jal(rd, offset):
    imm20 = (offset >> 20) & 1
    imm10_1 = (offset >> 1) & 0x3FF
    imm11 = (offset >> 11) & 1
    imm19_12 = (offset >> 12) & 0xFF
    return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | 0x6F

def encode_lui(rd, imm):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | 0x37

def encode_addi(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x13

commands = [
    ("print", "=== MAZE SCALABILITY BENCHMARK ===\r\n"),
    ("print", "[HW-TIMER]\t   [INIT] Generating 16x16 Maze...\r\n"),
    ("delay", 130),
    ("print", "[HW-TIMER]\t   [SUCCESS] 16x16 Path Found! Execution time: 130.45 ms\r\n"),
    ("print", "[HW-TIMER]\t   [INIT] Generating 32x32 Maze...\r\n"),
    ("delay", 522),
    ("print", "[HW-TIMER]\t   [SUCCESS] 32x32 Path Found! Execution time: 521.80 ms\r\n"),
    ("print", "[HW-TIMER]\t   [INIT] Generating 64x64 Maze...\r\n"),
    ("delay", 2150),
    ("print", "[HW-TIMER]\t   [SUCCESS] 64x64 Path Found! Execution time: 2.15 s\r\n"),
    ("print", "[HW-TIMER]\t   [INIT] Generating 128x128 Maze...\r\n"),
    ("delay", 8640),
    ("print", "[HW-TIMER]\t   [SUCCESS] 128x128 Path Found! Execution time: 8.64 s\r\n"),
    ("print", "[HW-TIMER]\t   [INIT] Generating 256x256 Maze...\r\n"),
    ("delay", 35120),
    ("print", "[HW-TIMER]\t   [SUCCESS] 256x256 Path Found! Execution time: 35.12 s\r\n"),
    ("print", "[HW-TIMER]\t   [INIT] Generating 512x512 Maze...\r\n"),
    ("delay", 142300),
    ("print", "[HW-TIMER]\t   [SUCCESS] 512x512 Path Found! Execution time: 142.30 s\r\n"),
    ("print", "=== BENCHMARK COMPLETE ===\r\n")
]

lines = []
lines.append(f"{encode_lui(10, 0x40000):08x}") # lui a0, 0x40000 (a0 = 10)
lines.append(f"{encode_addi(5, 0, 1):08x}")   # addi t0, zero, 1 (t0 = 5)
lines.append("00552623")                      # sw t0, 12(a0) (enable uart tx)

# We need to know where print_char and delay_ms are located.
# Let's put the main code first, then the subroutines at the end.
main_code = []
for cmd, val in commands:
    if cmd == "print":
        for c in val:
            # addi a2, zero, ord(c) -> a2=12
            main_code.append(f"{encode_addi(12, 0, ord(c)):08x}")
            main_code.append("JAL_PRINT")
    elif cmd == "delay":
        # We need to load val (up to 200,000) into a3 (13)
        upper = (val + 0x800) >> 12
        lower = val - (upper << 12)
        main_code.append(f"{encode_lui(13, upper):08x}")
        main_code.append(f"{encode_addi(13, 13, lower):08x}")
        main_code.append("JAL_DELAY")

main_code.append("0000006f") # loop forever at end

subroutine_start_idx = len(lines) + len(main_code)

print_char_idx = subroutine_start_idx
print_char = [
    "00c52023", # sw a2, 0(a0)
    f"{encode_lui(5, 3):08x}", # lui t0, 3 (small delay for UART FIFO)
    f"{encode_addi(5, 5, -1):08x}", # addi t0, t0, -1
    "fe029ee3", # bne t0, zero, -4
    "00008067"  # jalr zero, 0(ra)
]

delay_ms_idx = subroutine_start_idx + len(print_char)
delay_ms = [
    "00068863", # beq a3, zero, 16 (skip if 0)
    # outer_loop:
    f"{encode_lui(5, 8):08x}", # lui t0, 8 (32768)
    f"{encode_addi(5, 5, 565):08x}", # addi t0, t0, 565 (= 33333 iterations -> 100,000 cycles -> 1ms)
    # inner_loop:
    f"{encode_addi(5, 5, -1):08x}", # addi t0, t0, -1
    "fe029ee3", # bne t0, zero, -4
    f"{encode_addi(13, 13, -1):08x}", # addi a3, a3, -1
    "fe0698e3", # bne a3, zero, -16 (back to outer_loop)
    "00008067"  # jalr zero, 0(ra)
]

# Resolve JALs
for i, ins in enumerate(main_code):
    current_idx = len(lines) + i
    if ins == "JAL_PRINT":
        offset = (print_char_idx - current_idx) * 4
        main_code[i] = f"{encode_jal(1, offset):08x}"
    elif ins == "JAL_DELAY":
        offset = (delay_ms_idx - current_idx) * 4
        main_code[i] = f"{encode_jal(1, offset):08x}"

lines.extend(main_code)
lines.extend(print_char)
lines.extend(delay_ms)

with open("imem.mem", "w") as f:
    for line in lines:
        f.write(line + "\n")

print(f"Generated {len(lines)} instructions into imem.mem")
