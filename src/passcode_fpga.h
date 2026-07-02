#ifndef PASSCODE_FPGA_H
#define PASSCODE_FPGA_H

#include "passcode_protocol.h"

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t command;
    uint32_t status;
#ifdef PASSCODE_ENABLE_MOCK
    char passcode[5];
#endif
} passcode_mock_registers_t;

typedef struct {
    bool mock;
    int fd;
    void *map_base;
    volatile uint32_t *command_reg;
    volatile uint32_t *status_reg;
    passcode_mock_registers_t mock_regs;
} passcode_fpga_t;

int passcode_fpga_open(passcode_fpga_t *dev, bool mock, uint32_t pio_base);
void passcode_fpga_close(passcode_fpga_t *dev);

uint32_t passcode_fpga_read(passcode_fpga_t *dev, uint32_t offset);
void passcode_fpga_write(passcode_fpga_t *dev, uint32_t offset, uint32_t value);
void passcode_fpga_send_command(passcode_fpga_t *dev, passcode_command_t command);
void passcode_fpga_reset_to_waiting(passcode_fpga_t *dev);
int passcode_fpga_wait_auth_result(passcode_fpga_t *dev, unsigned int timeout_seconds,
                                   unsigned int poll_ms, uint32_t *status_out);

const char *passcode_status_name(uint32_t status);
bool passcode_status_is_terminal(uint32_t status);
int passcode_append_log(const char *path, const char *event, passcode_fpga_t *dev);

#endif
