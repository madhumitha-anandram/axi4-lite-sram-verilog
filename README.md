
## What this project does

Implements an AXI4-Lite compliant subordinate (slave) that sits in front of a synchronous SRAM. An AXI4-Lite master (a processor, DMA controller, or test logic) can read and write to the SRAM using the full 5-channel AXI4 handshake protocol.

AXI4-Lite — the 5 channels

AXI4 uses 5 independent channels, each with its own valid/ready handshake. A transfer on any channel only happens when BOTH valid and ready are high on the same clock edge.

| Channel | Direction | Signals |
| --- | --- | --- |
| Write Address (AW) | Master → Sub | awaddr, awvalid, awready |
| Write Data (W) | Master → Sub | wdata, wvalid, wready |
| Write Response (B) | Sub → Master | bresp, bvalid, bready |
| Read Address (AR) | Master → Sub | araddr, arvalid, arready |
| Read Data (R) | Sub → Master | rdata, rresp, rvalid, rready |

Write path FSM — 3 states

IDLE ──(awvalid && awready)──► WRITE ──(wvalid && wready)──► RESP ──(bvalid && bready)──► IDLE

IDLE: awready=1, waiting for write address

WRITE: wready=1, waiting for write data. When handshake happens: latches data and address, fires ram_write_enable for exactly 1 cycle

RESP: asserts bvalid=1 with bresp=OKAY (2'b00). Waits for master to accept with bready

Read path FSM — 3 states

R_IDLE ──(arvalid && arready)──► R_ADDR ──(1 cycle wait)──► R_DATA ──(rvalid && rready)──► R_IDLE

The extra R_ADDR state is critical — it gives read_addr_reg one cycle to settle before the RAM is read, preventing address-to-data glitches.

RAM address mux — write priority

assign ram_addr = ram_write_enable ? ram_write_addr : read_addr_reg;

When a write is happening, the RAM address mux gives priority to the write address. The ram_write_enable signal is registered (one-cycle pulse) so this priority is clean and glitch-free.

Response codes

| Response | Encoding | When used |
| --- | --- | --- |
| OKAY | 2'b00 | Successful transaction |
| SLVERR | 2'b10 | Subordinate error (out-of-range address) |

SRAM (ram_design.v)

Parameterized: addr_width=4, data_width=32, depth=16

Synchronous write (on clock edge when write_en=1)

Asynchronous read (combinational — rdata updates immediately when addr changes)

## File structure

axi_top_ram.v     — AXI4-Lite subordinate with write and read FSMs

ram_design.v      — Synchronous-write, async-read SRAM

axi_top_ram_tb.v  — Testbench: write then read back, verifies data integrity
