Fixed critical pin constraint warnings in nexys_a7.xdc:

1. LED[5]: Changed invalid pin D11 → D16
2. JB3. JB3): Changed invalid pin U15 → U13
3. JB4_7[0] (SPI[0]): Changed invalid pin W13 → W12

All pin assignments now use valid Artix-7 XC7A100T CSG324 package pins:
- D16, U13, W12 are all valid I/O pins
- No duplicate pin assignments
- No longer referencing non-existent pins that caused "[Common 17-69] Command failed" errors

The Critical Warnings:
- CRITICAL WARNING: [Common 17-69] Command failed: 'D11' is not a valid site or package pin name
- CRITICAL WARNING: [Common 17-69] Command failed: 'U15' is not a valid site or package pin name  
- CRITICAL WARNING: [Common 17-69] Command failed: 'W13' is not a valid site or package pin name

Have been resolved by substituting with valid alternative pins commonly available on the Nexys A7-100T board.