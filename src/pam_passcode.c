#define _POSIX_C_SOURCE 200809L

#include "passcode_fpga.h"

#include <security/pam_appl.h>
#include <security/pam_modules.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PASSCODE_PAM_LOG_PATH "/var/log/pam_passcode.log"

typedef struct {
    bool mock;
    unsigned int timeout_seconds;
    unsigned int poll_ms;
} pam_passcode_options_t;

static void parse_options(int argc, const char **argv, pam_passcode_options_t *options) {
#ifdef PASSCODE_ENABLE_MOCK
    options->mock = true;
#else
    options->mock = false;
#endif
    options->timeout_seconds = 30;
    options->poll_ms = 50;

    /* PAM module arguments are written as key=value tokens in PAM service files. */
    for (int i = 0; i < argc; i++) {
        if (strncmp(argv[i], "timeout=", 8) == 0) {
            sscanf(argv[i] + 8, "%u", &options->timeout_seconds);
        } else if (strncmp(argv[i], "poll_ms=", 8) == 0) {
            sscanf(argv[i] + 8, "%u", &options->poll_ms);
        }
    }
}

static void send_pam_info(pam_handle_t *pamh, const char *message) {
    const struct pam_conv *conv = NULL;
    struct pam_message msg = {
        .msg_style = PAM_TEXT_INFO,
        .msg = (char *)message,
    };
    const struct pam_message *msgp = &msg;
    struct pam_response *response = NULL;

    /* Use the application's PAM conversation to display short user guidance. */
    if (pam_get_item(pamh, PAM_CONV, (const void **)&conv) == PAM_SUCCESS &&
        conv != NULL && conv->conv != NULL) {
        conv->conv(1, &msgp, &response, conv->appdata_ptr);
    }
    free(response);
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags,
                                   int argc, const char **argv) {
    (void)flags;

    pam_passcode_options_t options;
    parse_options(argc, argv, &options);

    passcode_fpga_t dev;
    if (passcode_fpga_open(&dev, options.mock, PASSCODE_PIO_BASE) != 0) {
        send_pam_info(pamh, "FPGA authentication device is unavailable.");
        return PAM_AUTHINFO_UNAVAIL;
    }

    if (passcode_status_code(passcode_fpga_read(&dev, PASSCODE_REG_STATUS)) !=
        PASSCODE_STATUS_WAITING_COMMANDS) {
        send_pam_info(pamh, "FPGA authentication device is busy.");
        passcode_append_log(PASSCODE_PAM_LOG_PATH, "busy", &dev);
        passcode_fpga_close(&dev);
        return PAM_AUTH_ERR;
    }

    send_pam_info(pamh, "Enter passcode on the external keypad.");

    /* Start FPGA-side keypad authentication and wait for a terminal STATUS. */
    passcode_fpga_send_command(&dev, PASSCODE_CMD_AUTH);

    uint32_t status = PASSCODE_STATUS_WAITING_COMMANDS;
    int wait_rc = passcode_fpga_wait_auth_result(&dev, options.timeout_seconds,
                                                 options.poll_ms, &status);

    int pam_rc = PAM_AUTH_ERR;
    if (wait_rc != 0) {
        send_pam_info(pamh, "FPGA authentication timed out.");
        passcode_append_log(PASSCODE_PAM_LOG_PATH, "timeout", &dev);
    } else if (passcode_status_code(status) == PASSCODE_STATUS_AUTH_SUCCESS) {
        send_pam_info(pamh, "FPGA authentication accepted.");
        passcode_append_log(PASSCODE_PAM_LOG_PATH, "success", &dev);
        pam_rc = PAM_SUCCESS;
    } else {
        send_pam_info(pamh, "FPGA authentication rejected.");
        passcode_append_log(PASSCODE_PAM_LOG_PATH, "failure", &dev);
    }

    if (wait_rc == 0) {
        passcode_fpga_reset_to_waiting(&dev);
    }

    passcode_fpga_close(&dev);
    return pam_rc;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags,
                              int argc, const char **argv) {
    (void)pamh;
    (void)flags;
    (void)argc;
    (void)argv;
    return PAM_SUCCESS;
}
