#define _POSIX_C_SOURCE 200809L

#include "passcode_fpga.h"

#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

const char *passcode_status_name(uint32_t status) {
    switch (passcode_status_code(status)) {
    case PASSCODE_STATUS_WAITING_COMMANDS:
        return "waiting_commands";
    case PASSCODE_STATUS_INPUT_PASSWORD:
        return "input_password";
    case PASSCODE_STATUS_AUTH_SUCCESS:
        return "auth_success";
    case PASSCODE_STATUS_AUTH_FAIL:
        return "auth_fail";
    case PASSCODE_STATUS_INPUT_CURRENT_PASSCODE:
        return "input_current_passcode";
    case PASSCODE_STATUS_INPUT_NEW_PASSCODE:
        return "input_new_passcode";
    case PASSCODE_STATUS_PASSCODE_CHANGE_SUCCESS:
        return "passcode_change_success";
    case PASSCODE_STATUS_PASSCODE_CHANGE_FAIL:
        return "passcode_change_fail";
    case PASSCODE_STATUS_ERROR:
        return "error";
    default:
        return "unknown";
    }
}

bool passcode_status_is_terminal(uint32_t status) {
    uint32_t code = passcode_status_code(status);

    return code == PASSCODE_STATUS_AUTH_SUCCESS ||
           code == PASSCODE_STATUS_AUTH_FAIL ||
           code == PASSCODE_STATUS_PASSCODE_CHANGE_SUCCESS ||
           code == PASSCODE_STATUS_PASSCODE_CHANGE_FAIL ||
           code == PASSCODE_STATUS_ERROR;
}

static volatile uint32_t *pio_register(void *map_base, uint32_t pio_base,
                                       uint32_t byte_offset) {
    unsigned long mapped_offset =
        (unsigned long)(PASSCODE_LWFPGASLVS_OFST + pio_base + byte_offset) &
        (unsigned long)PASSCODE_HW_REGS_MASK;

    return (volatile uint32_t *)((char *)map_base + mapped_offset);
}

int passcode_fpga_open(passcode_fpga_t *dev, bool mock, uint32_t pio_base) {
    memset(dev, 0, sizeof(*dev));
    dev->fd = -1;
    dev->mock = mock;

#ifdef PASSCODE_ENABLE_MOCK
    /* Mock mode keeps a small in-memory register block for local testing. */
    if (mock) {
        dev->mock_regs.status = PASSCODE_STATUS_WAITING_COMMANDS;
        memcpy(dev->mock_regs.passcode, "1234", sizeof(dev->mock_regs.passcode));
        dev->command_reg = &dev->mock_regs.command;
        dev->status_reg = &dev->mock_regs.status;
        return 0;
    }
#else
    (void)mock;
#endif

    /*
     * Real mode follows the provided DE10-Nano reference:
     * map the HPS register span, then add the lightweight bridge offset.
     */
    dev->fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (dev->fd < 0) {
        return -1;
    }

    dev->map_base = mmap(NULL, PASSCODE_HW_REGS_SPAN, PROT_READ | PROT_WRITE,
                         MAP_SHARED, dev->fd, (off_t)PASSCODE_HW_REGS_BASE);
    if (dev->map_base == MAP_FAILED) {
        close(dev->fd);
        dev->fd = -1;
        dev->map_base = NULL;
        return -1;
    }

    dev->command_reg = pio_register(dev->map_base, pio_base, PASSCODE_COMMAND_OFFSET);
    dev->status_reg = pio_register(dev->map_base, pio_base, PASSCODE_STATUS_OFFSET);
    return 0;
}

void passcode_fpga_close(passcode_fpga_t *dev) {
    if (!dev->mock && dev->map_base != NULL) {
        munmap(dev->map_base, PASSCODE_HW_REGS_SPAN);
    }
    if (dev->fd >= 0) {
        close(dev->fd);
    }
}

uint32_t passcode_fpga_read(passcode_fpga_t *dev, uint32_t offset) {
    if (offset == PASSCODE_REG_COMMAND) {
        return *dev->command_reg;
    }
    if (offset == PASSCODE_REG_STATUS) {
        return *dev->status_reg;
    }
    return 0;
}

void passcode_fpga_write(passcode_fpga_t *dev, uint32_t offset, uint32_t value) {
    if (offset == PASSCODE_REG_COMMAND) {
        *dev->command_reg = value;
    } else if (offset == PASSCODE_REG_STATUS) {
        *dev->status_reg = value;
    }
}

static void mock_apply_command(passcode_fpga_t *dev, passcode_command_t command) {
#ifdef PASSCODE_ENABLE_MOCK
    if (!dev->mock) {
        return;
    }

    /* Simulate the FPGA entering the first state for each command. */
    if (command == PASSCODE_CMD_AUTH) {
        dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_INPUT_PASSWORD, 0);
    } else if (command == PASSCODE_CMD_CHANGE_PASSCODE) {
        dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_INPUT_CURRENT_PASSCODE, 0);
    }
#else
    (void)dev;
    (void)command;
#endif
}

void passcode_fpga_send_command(passcode_fpga_t *dev, passcode_command_t command) {
    passcode_fpga_write(dev, PASSCODE_REG_COMMAND, command);
    mock_apply_command(dev, command);
}

void passcode_fpga_reset_to_waiting(passcode_fpga_t *dev) {
    passcode_fpga_write(dev, PASSCODE_REG_COMMAND, PASSCODE_CMD_NONE);
#ifdef PASSCODE_ENABLE_MOCK
    if (dev->mock) {
        passcode_fpga_write(dev, PASSCODE_REG_STATUS, PASSCODE_STATUS_WAITING_COMMANDS);
    }
#endif
}

int passcode_fpga_wait_auth_result(passcode_fpga_t *dev, unsigned int timeout_seconds,
                                   unsigned int poll_ms, uint32_t *status_out) {
    const unsigned int effective_poll_ms = poll_ms == 0 ? 50 : poll_ms;
    const unsigned int max_polls = (timeout_seconds * 1000u) / effective_poll_ms;

    for (unsigned int poll = 0; poll <= max_polls; poll++) {
        uint32_t status = passcode_fpga_read(dev, PASSCODE_REG_STATUS);

        /* Terminal states are the only states PAM should convert to success/fail. */
        if (passcode_status_is_terminal(status)) {
            if (status_out != NULL) {
                *status_out = status;
            }
            return 0;
        }

#ifdef PASSCODE_ENABLE_MOCK
        /* PAM mock mode finishes successfully after a few polling cycles. */
        uint32_t status_code = passcode_status_code(status);

        if (dev->mock && status_code == PASSCODE_STATUS_INPUT_PASSWORD && poll >= 4) {
            dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_AUTH_SUCCESS, 4);
        } else if (dev->mock && status_code == PASSCODE_STATUS_INPUT_CURRENT_PASSCODE && poll >= 4) {
            dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_INPUT_NEW_PASSCODE, 0);
        } else if (dev->mock && status_code == PASSCODE_STATUS_INPUT_NEW_PASSCODE && poll >= 8) {
            dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_PASSCODE_CHANGE_SUCCESS, 4);
        }
#endif

        struct timespec delay = {
            .tv_sec = effective_poll_ms / 1000u,
            .tv_nsec = (long)(effective_poll_ms % 1000u) * 1000000L,
        };
        nanosleep(&delay, NULL);
    }

    return -1;
}

int passcode_append_log(const char *path, const char *event, passcode_fpga_t *dev) {
    FILE *file = fopen(path, "a");
    if (file == NULL) {
        return -1;
    }

    time_t now = time(NULL);
    struct tm tm_buf;
    localtime_r(&now, &tm_buf);

    char timestamp[32];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", &tm_buf);

    uint32_t status = passcode_fpga_read(dev, PASSCODE_REG_STATUS);

    /* Keep logs simple enough to inspect during FPGA/PAM integration tests. */
    fprintf(file, "%s event=%s status=%s status_code=%" PRIu32
            " digits=%" PRIu32 " raw_status=%" PRIu32 "\n",
            timestamp,
            event,
            passcode_status_name(status),
            passcode_status_code(status),
            passcode_status_digits(status),
            status);

    fclose(file);
    return 0;
}
