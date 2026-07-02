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
| `passcode/password_pio.v` | Custom Avalon-MM command/status PIO registers. |
| `passcode/password_system.v` | Platform Designer component wrapper around the passcode core and custom PIOs. |

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

## Custom PIO Component

Use `passcode/password_system.v` as a custom Platform Designer component. This
keeps the Linux interface close to the `MyPIO` exercise while still wrapping the
passcode core.

The component has two Avalon-MM slave interfaces:

| Interface | Purpose |
| --- | --- |
| `command_slave` | Linux writes command values, FPGA reads them. |
| `status_slave` | FPGA publishes status, Linux reads it. |

Register map:

| Interface | Address | Direction | Description |
| --- | --- | --- | --- |
| `command_slave` | `0x0` | HPS write/read | `0`: none, `1`: auth, `2`: change passcode |
| `status_slave` | `0x0` | HPS read, optional debug write | `status_raw[7:0]`: status, `status_raw[15:8]`: digit count |

In Platform Designer:

1. Open `soc_system.qsys`.
2. Select `File` -> `New Component`.
3. Add these files in the `Files` tab:
   - `passcode/password_system.v`
   - `passcode/password_pio.v`
   - `passcode/password.v`
   - `passcode/keyboard_scan.v`
4. Set the top module to `password_system`.
5. Click `Analyze Synthesis Files`.
6. Create/export these conduit signals:
   - `row[3:0]`
   - `col[3:0]`
   - `led[3:0]`
7. Create two Avalon-MM slave interfaces:
   - `command_slave`: `command_address`, `command_read`, `command_readdata`, `command_write`, `command_writedata`
   - `status_slave`: `status_address`, `status_read`, `status_readdata`, `status_write`, `status_writedata`
8. Associate both Avalon-MM slave interfaces with `clk` and `reset`.
9. Save the component as `password_system`.
10. Add `password_system` to `soc_system`.
11. Connect both slave interfaces to the HPS lightweight bridge path, like the `MyPIO` exercise.
12. Export the keypad/LED conduit as needed.

Recommended base addresses:

| Interface | Base |
| --- | --- |
| `password_system.command_slave` | `0x00003000` |
| `password_system.status_slave` | `0x00003010` |

## Top-Level Wiring

After Platform Designer regenerates `soc_system`, wire the exported keypad
conduit ports in `DE10_NANO_SoC_GHRD.v`.

Do this after HDL generation, because the `soc_system` port list changes only
after Platform Designer exports the `password_system` conduit.

The generated `soc_system` module should contain ports similar to:

```verilog
password_system_0_row_export
password_system_0_col_export
password_system_0_led_export
```

Connect those exported ports to the physical keypad pins/signals:

```verilog
.password_system_0_row_export(<keypad_row_signal>),
.password_system_0_col_export(<keypad_col_signal>),
.password_system_0_led_export(<passcode_led_signal>),
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
