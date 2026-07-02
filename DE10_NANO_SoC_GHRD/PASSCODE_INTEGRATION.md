# Passcode Integration Notes

This GHRD project is the hardware base for connecting the Linux-side passcode
program to FPGA logic.

Use the GHRD project as the starting point. It already contains the HPS,
lightweight HPS-to-FPGA bridge, reset wiring, and DE10-Nano pin assignments that
the Linux `/dev/mem` code expects.

## Files

| File | Purpose |
| --- | --- |
| `passcode/command_pio.v` | MyPIO-style command register. Linux writes command values, FPGA reads `command`. |
| `passcode/status_pio.v` | MyPIO-style status register. FPGA writes `status_next`, Linux reads status values. |
| `passcode/password.v` | Passcode state machine and keypad authentication logic. |
| `passcode/keyboard_scan.v` | 4x4 keypad scanner used by `password.v`. |

## Platform Designer Components

Create two custom components from separate files.

### command_pio

Top module:

```text
command_pio
```

Avalon-MM slave interface `s1`:

- `address`
- `read`
- `readdata`
- `write`
- `writedata`

Conduit:

- `command[31:0]`

Recommended base address:

```text
0x00003500
```

### status_pio

Top module:

```text
status_pio
```

Avalon-MM slave interface `s1`:

- `address`
- `read`
- `readdata`
- `write`
- `writedata`

Conduit:

- `status_next[31:0]`

Recommended base address:

```text
0x00003510
```

## Connections

Connect both `s1` slave interfaces to the HPS lightweight bridge path, like the
`MyPIO` exercise. Do not connect them to `f2sdram_only_master.master`.

Use top-level wires in `DE10_NANO_SoC_GHRD.v` after Platform Designer
regenerates `soc_system`:

```verilog
wire [31:0] passcode_command;
wire [31:0] passcode_status;
```

Connect the generated `soc_system` exports:

```verilog
.command_pio_0_command_export(passcode_command),
.status_pio_0_status_next_export(passcode_status),
```

Connect the passcode core:

```verilog
password password_inst (
    .clk(FPGA_CLK1_50),
    .rst_n(hps_fpga_reset_n),
    .command(passcode_command),
    .row(<keypad_row_signal>),
    .col(<keypad_col_signal>),
    .status_raw(passcode_status),
    .led()
);
```

Replace `<keypad_row_signal>` and `<keypad_col_signal>` with the actual GPIO
signals used for the keypad.

## Linux-Side Update

After generating HDL, check the generated `hps_0.h` or system header for the
PIO base addresses and copy them to:

```c
#define PASSCODE_COMMAND_PIO_BASE   0x00003500u
#define PASSCODE_STATUS_PIO_BASE    0x00003510u
```

in `src/passcode_protocol.h`.

Do not copy these addresses blindly if Platform Designer assigns different
values. The generated header is the source of truth.
