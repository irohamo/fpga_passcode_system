# DE10-Nano Passcode System - Linux Side

This directory contains the Linux-side implementation for the passcode authentication system described in `IoTシステム設計.pdf`.

The Linux side is responsible for two modules:

- Module 5: Command input module
  - Notify the FPGA to start the passcode system.
- Module 6: Status display and log module
  - Receive authentication status from the FPGA.
  - Display status in the terminal.
  - Convert FPGA status into a PAM authentication result.
  - Save authentication logs.

## FPGA Interface

This project follows the address-mapping style used by the provided `src/main.c` reference file and uses two Platform Designer PIO components.

The Linux program accesses FPGA registers from the DE10-Nano HPS through `/dev/mem`. Like `src/main.c`, it maps the HPS register span from `ALT_STM_OFST` (`0xfc000000`) and then computes the lightweight bridge address with:

```c
virtual_base + ((ALT_LWFPGASLVS_OFST + pio_base) & HW_REGS_MASK)
```

The PIO base address should be copied from `hps_0.h`. Set it in
`src/passcode_protocol.h`:

```c
#define PASSCODE_PIO_BASE   0x00000000u
```

Linux and FPGA share one custom Avalon-MM PIO component with two registers:

| Register | Byte offset | Direction | Description |
| --- | --- | --- | --- |
| `COMMAND` | `0x00` | Linux -> FPGA | `1`: auth, `2`: change passcode |
| `STATUS` | `0x04` | FPGA -> Linux | state code and entered digit count |

`COMMAND` values:

| Value | Name | Meaning |
| --- | --- | --- |
| `0` | `NONE` | Waiting for commands |
| `1` | `AUTH` | Start normal authentication |
| `2` | `CHANGE_PASSCODE` | Start passcode change flow |

`STATUS` bit layout:

| Bits | Name | Meaning |
| --- | --- | --- |
| `7..0` | `STATUS_CODE` | state code shown below |
| `15..8` | `DIGITS` | number of entered passcode digits |

For example, if the FPGA is waiting for password input and two digits have
been entered, write:

```c
STATUS = 1 | (2 << 8);
```

The Linux side prints this as
`status=input_password status_code=1 digits=2 passcode=**__`.
During `auth`, `change`, and `watch`, the command-line tool prints one line for
each `STATUS` change, so digit changes remain visible in the terminal log.

`STATUS_CODE` values:

| Value | Name | Meaning |
| --- | --- | --- |
| `0` | `WAITING_COMMANDS` | Waiting for a Linux command |
| `1` | `INPUT_PASSWORD` | Waiting for passcode input |
| `2` | `AUTH_SUCCESS` | Authentication succeeded |
| `3` | `AUTH_FAIL` | Authentication failed |
| `4` | `INPUT_CURRENT_PASSCODE` | Waiting for the current passcode during change flow |
| `5` | `INPUT_NEW_PASSCODE` | Waiting for the new passcode |
| `6` | `PASSCODE_CHANGE_SUCCESS` | Passcode changed successfully |
| `7` | `PASSCODE_CHANGE_FAIL` | Passcode change failed |
| `8` | `ERROR` | General input or state error |

Keypad scanning, passcode comparison, passcode change, digit counting, and A/B/C/D key handling are done on the FPGA side. The Linux side writes `COMMAND` and monitors `STATUS`.

After Linux reads a terminal result, it acknowledges the result by writing
`COMMAND=0`. The FPGA should then return `STATUS` to `WAITING_COMMANDS`
(`0`) after it observes `COMMAND=0`.

## Quartus / GHRD Integration

The main hardware integration work now lives under `DE10_NANO_SoC_GHRD/`.
Use that project as the base because it already contains the HPS, lightweight
HPS-to-FPGA bridge, clocks, resets, and DE10-Nano pin assignments.

| File | Purpose |
| --- | --- |
| `DE10_NANO_SoC_GHRD/passcode/passcode_pio.v` | Single-file Platform Designer component. It contains the custom Avalon-MM PIO, passcode state machine, and keypad scanner. |
| `DE10_NANO_SoC_GHRD/PASSCODE_INTEGRATION.md` | Step-by-step GHRD wiring notes. |
| `quartus/` | Standalone/reference Quartus project for the passcode core. |

In the GHRD flow, add `passcode_pio` as a custom Platform Designer component.
It exposes one Avalon-MM slave interface:

| Interface | Width | Purpose |
| --- | --- | --- |
| `s1` | 32 | Linux writes command at address 0 and reads status at address 1. |

Wire it as:

```text
Linux /dev/mem -> HPS lightweight bridge -> passcode_pio.s1
passcode_pio.address=0 -> COMMAND
passcode_pio.address=1 -> STATUS
```

After HDL generation, copy the generated base address from `hps_0.h` into
`PASSCODE_PIO_BASE`.

## Build

Build the production command-line tool:

```sh
make
```

Build the mock command-line tool:

```sh
make mock
```

Build the production PAM module:

```sh
make pam
```

Build the mock PAM module:

```sh
make pam-mock
```

If the DE10-Nano Linux environment does not have PAM development headers, the build may fail with `security/pam_modules.h` not found. Install the package equivalent to `libpam0g-dev` for your distribution.

## Command-Line Usage

Run on the DE10-Nano with real FPGA registers:

```sh
sudo ./build/passcodectl start
sudo ./build/passcodectl auth
sudo ./build/passcodectl change
sudo ./build/passcodectl watch
sudo ./build/passcodectl status
```

If your Platform Designer PIO base address is not the placeholder value, copy
the value from `hps_0.h`:

Update `PASSCODE_PIO_BASE` in `src/passcode_protocol.h`.

Run without FPGA hardware:

```sh
./build/passcodectl_mock start
./build/passcodectl_mock auth
./build/passcodectl_mock change
./build/passcodectl_mock watch
```

The production `passcodectl` binary does not include mock mode. Mock behavior is built into `passcodectl_mock`, which uses `1234` as the initial passcode.

`passcodectl_mock auth` reads numeric keyboard inputs as keypad digits. It
updates `passcode=____`, `passcode=*___`, and so on while typing. Press Enter
after four digits to submit.

`passcodectl_mock change` reads the current passcode first, then reads the new
4-digit passcode in the same key-by-key style. Press Enter after each 4-digit
passcode.

`passcodectl_mock watch` starts an interactive mock console:

```text
mock command [a=auth, c=change, s=status, q=quit]:
```

`start` writes `COMMAND=1` and prints the current status once. Use `auth`, `change`, or `watch` when you want to wait until the FPGA reports a terminal result.

## PAM Usage

`pam_passcode.so` runs during the PAM `auth` phase. It sends the start command to the FPGA and waits for the keypad authentication result.

Flow:

1. The PAM service calls `pam_sm_authenticate()`.
2. Linux writes `COMMAND=1` to the FPGA.
3. The user enters the passcode on the 4x4 keypad.
4. The FPGA updates `STATUS`.
5. `STATUS=2` becomes `PAM_SUCCESS`; `STATUS=3`, `7`, or `8` becomes authentication failure.

Build:

```sh
make pam
```

Install:

```sh
sudo make install-pam
```

If your PAM module directory is different, pass `PAM_LIBDIR`.

```sh
sudo make install-pam PAM_LIBDIR=/lib/arm-linux-gnueabihf/security
```

Start with a test PAM service so you do not break `login` or `sudo`.

`/etc/pam.d/passcode-test`:

```text
auth required pam_passcode.so timeout=30 poll_ms=50
account required pam_permit.so
```

Build the PAM test program:

```sh
make pam-test
```

Run the test:

```sh
sudo ./build/pam_test passcode-test root
```

Do not edit `login` or `sudo` first. Confirm the behavior through `passcode-test`, then integrate the module into the target service.

Mock PAM build and test:

```sh
make pam-mock
sudo make install-pam-mock
```

```text
auth required pam_passcode_mock.so timeout=5
account required pam_permit.so
```

PAM options:

| Option | Default | Description |
| --- | --- | --- |
| `timeout=30` | `30` | Timeout in seconds while waiting for the FPGA result |
| `poll_ms=50` | `50` | STATUS register polling interval |
| `mock` | n/a | Mock behavior is selected by building `pam_passcode_mock.so` |

## Items To Confirm With The FPGA Side

- Actual PIO base address in `hps_0.h`, for example `PASSCODE_PIO_BASE`.
- That `COMMAND` is at byte offset `0x00` and `STATUS` is at byte offset `0x04`.
- Whether `STATUS[7:0]` is the state code and `STATUS[15:8]` is the digit count.
- When the FPGA changes `STATUS` after receiving `COMMAND=1` or `COMMAND=2`.
- Whether the status code table above matches the Verilog implementation.
- That Linux acknowledges terminal results by writing `COMMAND=0`, and the FPGA then resets `STATUS=0`.
- Which PAM service should use the FPGA authentication module. Use a test service first.
