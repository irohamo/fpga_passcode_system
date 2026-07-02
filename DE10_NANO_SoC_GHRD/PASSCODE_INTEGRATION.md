# Passcode Integration Notes

This GHRD project is the hardware base for connecting the Linux-side passcode
program to FPGA logic.

Use the GHRD project as the starting point. It already contains the HPS,
lightweight HPS-to-FPGA bridge, reset wiring, and DE10-Nano pin assignments that
the Linux `/dev/mem` code expects.

## Files

| File | Purpose |
| --- | --- |
| `passcode/passcode_pio.v` | Single-file custom Avalon-MM PIO component. It only contains the HPS-facing command/status register block. |
| `passcode/password.v` | Passcode state machine and keypad authentication logic. |
| `passcode/keyboard_scan.v` | 4x4 keypad scanner used by `password.v`. |

## Custom PIO Component

Use `passcode/passcode_pio.v` as a custom Platform Designer component.

Top module:

```text
passcode_pio
```

The component has one Avalon-MM slave interface:

| Interface | Purpose |
| --- | --- |
| `s1` | HPS reads/writes the passcode register block. |

Register map:

| Address | Byte offset | Direction | Description |
| --- | --- | --- | --- |
| `0` | `0x00` | HPS write/read | `COMMAND`: `0`: none, `1`: auth, `2`: change passcode |
| `1` | `0x04` | HPS read, optional debug write | `STATUS`: `status_raw[7:0]`: status, `status_raw[15:8]`: digit count |

In Platform Designer:

1. Open `soc_system.qsys`.
2. Select `File` -> `New Component`.
3. Add `passcode/passcode_pio.v` in the `Files` tab.
4. Set the top module to `passcode_pio`.
5. Click `Analyze Synthesis Files`.
6. Create one Avalon-MM slave interface, for example `s1`:
   - `address`
   - `read`
   - `readdata`
   - `write`
   - `writedata`
7. Associate `s1` with `clk` and `reset`.
8. Do not create extra conduit signals for this component.
9. Save the component as `passcode_pio`.
10. Add `passcode_pio` to `soc_system`.
11. Connect `s1` to the HPS lightweight bridge path, like the `MyPIO` exercise.
12. Do not connect it to `f2sdram_only_master.master`.

Recommended base address:

| Interface | Base |
| --- | --- |
| `passcode_pio.s1` | `0x00003500` |

Do not use `0x00003000` if `led_pio.s1` is still in the GHRD system, because
the default GHRD LED PIO often already occupies `0x00003000..0x0000300f`.

Connect `passcode_pio.s1` only to the HPS lightweight bridge path used by
`led_pio`, `dipsw_pio`, and `button_pio`. Do not connect it to
`f2sdram_only_master.master`; that master spans the SDRAM address space and will
overlap the custom PIO address range.

## Top-Level Wiring

After Platform Designer regenerates `soc_system`, `passcode_pio` should not add
any new top-level conduit ports. It should only appear as an HPS-visible
Avalon-MM slave register block.

The passcode authentication logic is intentionally separate from this PIO file.
Use `password.v` and `keyboard_scan.v` for the keypad/passcode side.

## Linux-Side Update

After generating HDL, check the generated `hps_0.h` or system header for the
PIO base address and copy it to:

```c
#define PASSCODE_PIO_BASE 0x00003500u
```

in `src/passcode_protocol.h`.

Do not copy the recommended address blindly if Platform Designer assigns a
different value. The generated header is the source of truth.
