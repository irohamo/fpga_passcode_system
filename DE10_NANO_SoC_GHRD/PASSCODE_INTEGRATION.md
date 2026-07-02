# Passcode Integration Notes

This GHRD project is the hardware base for connecting the Linux-side passcode
program to FPGA logic.

Use the GHRD project as the starting point. It already contains the HPS,
lightweight HPS-to-FPGA bridge, reset wiring, and DE10-Nano pin assignments that
the Linux `/dev/mem` code expects.

## Files Added

| File | Purpose |
| --- | --- |
| `passcode/password.v` | Keypad passcode state machine. |
| `passcode/keyboard_scan.v` | 4x4 keypad scanner and debouncer. |

`password.v` exposes the Linux-facing signals:

```verilog
input  wire [31:0] command;
output wire [31:0] status_raw;
```

`status_raw` uses the same layout as the Linux code:

```text
status_raw[7:0]  = status code
status_raw[15:8] = entered digit count
```

## Platform Designer Work

Use standard Platform Designer PIO components. Custom PIO Verilog is not needed
for the GHRD flow.

Add two PIO components to `soc_system.qsys`:

| Component | Direction | Width | Purpose |
| --- | --- | --- | --- |
| `command_pio` | Output | 32 | Linux writes command, FPGA reads it. |
| `status_pio` | Input | 32 | FPGA writes status, Linux reads it. |

Recommended base addresses:

| Component | Base |
| --- | --- |
| `command_pio` | `0x00003000` |
| `status_pio` | `0x00003010` |

Connect both PIO slave ports to the lightweight HPS-to-FPGA bridge path, like
the `MyPIO` exercise.

Export both PIO external connections. After HDL generation, the generated
`soc_system` module should have ports similar to:

```verilog
command_pio_external_connection_export
status_pio_external_connection_export
```

## Top-Level Wiring

After Platform Designer regenerates `soc_system`, wire the exported PIO ports
to the passcode core in `DE10_NANO_SoC_GHRD.v`.

Do this after HDL generation, because the `soc_system` port list changes only
after Platform Designer exports `command_pio` and `status_pio`.

Add wires:

```verilog
wire [31:0] passcode_command;
wire [31:0] passcode_status;
```

Connect `soc_system` ports:

```verilog
.command_pio_external_connection_export(passcode_command),
.status_pio_external_connection_export(passcode_status),
```

Instantiate the passcode core:

```verilog
password password_inst (
    .clk(FPGA_CLK1_50),
    .rst_n(hps_fpga_reset_n),
    .command(passcode_command),
    .row(<keypad_row_signal>),
    .col(<keypad_col_signal>),
    .status_raw(passcode_status),
    .led(LED[3:0])
);
```

Replace `<keypad_row_signal>` and `<keypad_col_signal>` with the actual GPIO
signals used for the keypad.

If LED0 is useful for passcode debugging, keep the existing GHRD LED assignment
for `LED[7:1]` and drive only `LED[0]` from the passcode core, or route the
passcode `led[3:0]` to unused GPIO/LEDs after checking for conflicts.

## Linux-Side Update

After generating HDL, check the generated `hps_0.h` or system header for the
PIO base addresses and copy them to:

```c
#define PASSCODE_COMMAND_PIO_BASE   0x00003000u
#define PASSCODE_STATUS_PIO_BASE    0x00003010u
```

in `src/passcode_protocol.h`.

Do not copy the recommended addresses blindly if Platform Designer assigns
different values. The generated header is the source of truth.
