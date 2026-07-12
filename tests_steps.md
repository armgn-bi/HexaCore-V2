# ALINX AXU4EVB-P Hardware Test Log
This document logs every step taken during the hardware validation of the HexaCore-V2 project on the ALINX AXU4EVB-P development board.

## Test 1: Bitstream Programming and UART Validation

### Step 1: Vivado Project Setup & Compilation (Completed)
- **Action**: Created a new Vivado project (`hexacore_axu4evb`) targeting the Zynq UltraScale+ `xczu4ev-sfvc784-1-i` part.
- **Action**: Modified `dmem.sv` to ensure proper synchronous BRAM inference without asynchronous resets, resolving Synthesis Error 8-3391.
- **Action**: Ran synthesis, implementation, and generated the `.bit` file (`axu4evb_top.bit`) via automated TCL script.

### Step 2: Hardware Programming (Current Step)
- **Action**: Connected the JTAG cable and board power.
- **Action**: Opened Vivado Hardware Manager and connected to the target.
- **Action**: Selected `Program Device` for the XCZU4EV chip.
- **Action**: Selected the bitstream file `hexacore_axu4evb.runs/impl_1/axu4evb_top.bit`.
- **Result**: (Pending) Bitstream upload to the FPGA.

### Step 3: UART Terminal Setup (Completed)
- **Action**: Open terminal emulator (PuTTY, TeraTerm, MobaXTerm, etc.).
- **Action**: Select the COM port corresponding to the board's USB-to-UART bridge (COM5).
- **Action**: Set Baud Rate to 115200, Data Bits 8, Parity None, Stop Bits 1.
- **Result**: (Pending) Observe maze solving output on terminal.
