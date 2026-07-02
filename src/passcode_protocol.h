#ifndef PASSCODE_PROTOCOL_H
#define PASSCODE_PROTOCOL_H

#include <stdint.h>

/*
 * Address mapping style follows the DE10-Nano reference main.c:
 *   mmap ALT_STM_OFST for HW_REGS_SPAN bytes
 *   pio_base = virtual_base + ((ALT_LWFPGASLVS_OFST + pio_component_base)
 *                                   & HW_REGS_MASK)
 */
#define PASSCODE_HW_REGS_BASE       0xfc000000u
#define PASSCODE_HW_REGS_SPAN       0x04000000u
#define PASSCODE_HW_REGS_MASK       (PASSCODE_HW_REGS_SPAN - 1u)
#define PASSCODE_LWFPGASLVS_OFST    0xff200000u

/* Set this from the Platform Designer address in hps_0.h. */
#define PASSCODE_PIO_BASE           0x00000000u

/* Logical register IDs used by the Linux code. */
#define PASSCODE_REG_COMMAND 0u
#define PASSCODE_REG_STATUS  1u
#define PASSCODE_COMMAND_OFFSET     0x00u
#define PASSCODE_STATUS_OFFSET      0x04u

/*
 * STATUS register bit layout:
 *   bits  0..7  : state code
 *   bits  8..15 : number of entered passcode digits
 */
#define PASSCODE_STATUS_CODE_MASK   0x000000ffu
#define PASSCODE_STATUS_DIGITS_MASK 0x0000ff00u
#define PASSCODE_STATUS_DIGITS_SHIFT 8u

typedef enum {
    PASSCODE_CMD_NONE = 0,
    PASSCODE_CMD_AUTH = 1,
    PASSCODE_CMD_CHANGE_PASSCODE = 2,
} passcode_command_t;

/* STATUS is a single value register matching the agreed state diagram. */
typedef enum {
    PASSCODE_STATUS_WAITING_COMMANDS = 0,
    PASSCODE_STATUS_INPUT_PASSWORD = 1,
    PASSCODE_STATUS_AUTH_SUCCESS = 2,
    PASSCODE_STATUS_AUTH_FAIL = 3,
    PASSCODE_STATUS_INPUT_CURRENT_PASSCODE = 4,
    PASSCODE_STATUS_INPUT_NEW_PASSCODE = 5,
    PASSCODE_STATUS_PASSCODE_CHANGE_SUCCESS = 6,
    PASSCODE_STATUS_PASSCODE_CHANGE_FAIL = 7,
    PASSCODE_STATUS_ERROR = 8,
} passcode_status_t;

static inline uint32_t passcode_status_code(uint32_t raw_status) {
    return raw_status & PASSCODE_STATUS_CODE_MASK;
}

static inline uint32_t passcode_status_digits(uint32_t raw_status) {
    return (raw_status & PASSCODE_STATUS_DIGITS_MASK) >> PASSCODE_STATUS_DIGITS_SHIFT;
}

static inline uint32_t passcode_make_status(uint32_t status_code, uint32_t digits) {
    return (status_code & PASSCODE_STATUS_CODE_MASK) |
           ((digits << PASSCODE_STATUS_DIGITS_SHIFT) & PASSCODE_STATUS_DIGITS_MASK);
}

#endif
