#define _POSIX_C_SOURCE 200809L

#include "passcode_fpga.h"

#ifdef PASSCODE_ENABLE_MOCK
#include <ctype.h>
#include <termios.h>
#endif
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define PASSCODE_CLI_LOG_PATH "auth.log"

typedef struct {
    bool mock;
    const char *command;
} app_options_t;

static void usage(const char *program) {
    fprintf(stderr,
            "Usage: %s COMMAND\n"
            "\n"
            "Commands:\n"
            "  start    write CMD_AUTH to FPGA and print status once\n"
            "  auth     write CMD_AUTH and wait for auth success/fail\n"
            "  change   write CMD_CHANGE_PASSCODE and wait for change success/fail\n"
            "  watch    print status changes until Ctrl-C\n"
            "  status   print current FPGA status once\n",
            program);
}

static int parse_options(int argc, char **argv, app_options_t *options) {
#ifdef PASSCODE_ENABLE_MOCK
    options->mock = true;
#else
    options->mock = false;
#endif
    options->command = NULL;

    if (argc == 2) {
        options->command = argv[1];
    } else if (argc > 2) {
        fprintf(stderr, "too many arguments\n");
        return -1;
    }

    if (options->command == NULL) {
        return -1;
    }
    return 0;
}

static void format_passcode_view(uint32_t status, char passcode_view[5]) {
    uint32_t digits = passcode_status_digits(status);

    if (digits > 4) {
        digits = 4;
    }
    for (size_t i = 0; i < 4; i++) {
        passcode_view[i] = i < digits ? '*' : '_';
    }
    passcode_view[4] = '\0';
}

static void print_status(passcode_fpga_t *dev) {
    /* Show both the raw register value and a readable status name. */
    uint32_t command = passcode_fpga_read(dev, PASSCODE_REG_COMMAND);
    uint32_t status = passcode_fpga_read(dev, PASSCODE_REG_STATUS);
    char passcode_view[5];

    format_passcode_view(status, passcode_view);

    printf("command=%" PRIu32 " status=%s status_code=%" PRIu32
           " digits=%" PRIu32 " passcode=%s raw_status=%" PRIu32 "\n",
           command,
           passcode_status_name(status),
           passcode_status_code(status),
           passcode_status_digits(status),
           passcode_view,
           status);
    fflush(stdout);
}

static bool is_waiting_for_command(passcode_fpga_t *dev) {
    return passcode_status_code(passcode_fpga_read(dev, PASSCODE_REG_STATUS)) ==
           PASSCODE_STATUS_WAITING_COMMANDS;
}

static void sleep_ms(unsigned int milliseconds) {
    struct timespec delay = {
        .tv_sec = milliseconds / 1000u,
        .tv_nsec = (long)(milliseconds % 1000u) * 1000000L,
    };

    nanosleep(&delay, NULL);
}

static int reject_if_busy(passcode_fpga_t *dev, const char *log_path, const char *event) {
    if (is_waiting_for_command(dev)) {
        return 0;
    }

    fprintf(stderr, "FPGA is busy; command rejected.\n");
    print_status(dev);
    passcode_append_log(log_path, event, dev);
    return 1;
}

static int wait_result_with_status_updates(passcode_fpga_t *dev,
                                           unsigned int timeout_seconds,
                                           unsigned int poll_ms,
                                           uint32_t *status_out) {
    const unsigned int effective_poll_ms = poll_ms == 0 ? 50 : poll_ms;
    const unsigned int max_polls = (timeout_seconds * 1000u) / effective_poll_ms;
    uint32_t last_status = UINT32_MAX;

    for (unsigned int poll = 0; poll <= max_polls; poll++) {
        uint32_t status = passcode_fpga_read(dev, PASSCODE_REG_STATUS);

        if (status != last_status) {
            print_status(dev);
            last_status = status;
        }

        if (passcode_status_is_terminal(status)) {
            if (status_out != NULL) {
                *status_out = status;
            }
            return 0;
        }

        sleep_ms(effective_poll_ms);
    }

    return -1;
}

#ifdef PASSCODE_ENABLE_MOCK
static bool read_mock_line(const char *prompt, char *buffer, size_t size) {
    printf("%s", prompt);
    fflush(stdout);
    if (fgets(buffer, (int)size, stdin) == NULL) {
        return false;
    }

    size_t len = strlen(buffer);
    if (len > 0 && buffer[len - 1] == '\n') {
        buffer[len - 1] = '\0';
    }
    return true;
}

static bool mock_begin_key_input(struct termios *old_termios, bool *raw_enabled) {
    *raw_enabled = false;
    if (!isatty(STDIN_FILENO)) {
        return true;
    }
    if (tcgetattr(STDIN_FILENO, old_termios) != 0) {
        return false;
    }

    struct termios new_termios = *old_termios;
    new_termios.c_lflag &= (tcflag_t)~(ICANON | ECHO);
    new_termios.c_cc[VMIN] = 1;
    new_termios.c_cc[VTIME] = 0;

    if (tcsetattr(STDIN_FILENO, TCSANOW, &new_termios) != 0) {
        return false;
    }
    *raw_enabled = true;
    return true;
}

static void mock_end_key_input(const struct termios *old_termios, bool raw_enabled) {
    if (raw_enabled) {
        tcsetattr(STDIN_FILENO, TCSANOW, old_termios);
    }
}

static bool mock_read_passcode_keys(passcode_fpga_t *dev, uint32_t input_status,
                                    char passcode[5]) {
    struct termios old_termios;
    bool raw_enabled = false;
    size_t digits = 0;

    memset(passcode, 0, 5);
    if (!mock_begin_key_input(&old_termios, &raw_enabled)) {
        dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_ERROR, 0);
        print_status(dev);
        return false;
    }

    dev->mock_regs.status = passcode_make_status(input_status, 0);
    print_status(dev);

    while (true) {
        int ch = getchar();
        if (ch == EOF) {
            mock_end_key_input(&old_termios, raw_enabled);
            dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_ERROR, digits);
            print_status(dev);
            return false;
        }

        if (ch == '\n' || ch == '\r') {
            if (digits == 4) {
                break;
            }
            continue;
        }
        if (ch == 127 || ch == '\b') {
            if (digits > 0) {
                digits--;
                passcode[digits] = '\0';
            }
        } else if (isdigit((unsigned char)ch) && digits < 4) {
            passcode[digits] = (char)ch;
            digits++;
        } else if (isdigit((unsigned char)ch)) {
            continue;
        } else {
            mock_end_key_input(&old_termios, raw_enabled);
            dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_ERROR, digits);
            print_status(dev);
            return false;
        }

        dev->mock_regs.status = passcode_make_status(input_status, digits);
        print_status(dev);
    }

    mock_end_key_input(&old_termios, raw_enabled);
    return true;
}

static int mock_authenticate_once(passcode_fpga_t *dev, const char *log_path) {
    char input[5] = {0};

    if (reject_if_busy(dev, log_path, "mock_auth_busy") != 0) {
        return 1;
    }

    passcode_fpga_send_command(dev, PASSCODE_CMD_AUTH);

    if (!mock_read_passcode_keys(dev, PASSCODE_STATUS_INPUT_PASSWORD, input)) {
        passcode_append_log(log_path, "mock_auth", dev);
        passcode_fpga_reset_to_waiting(dev);
        return 1;
    } else if (strcmp(input, dev->mock_regs.passcode) == 0) {
        dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_AUTH_SUCCESS, 4);
    } else {
        dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_AUTH_FAIL, 4);
    }

    print_status(dev);
    passcode_append_log(log_path, "mock_auth", dev);
    int rc = passcode_status_code(dev->mock_regs.status) == PASSCODE_STATUS_AUTH_SUCCESS ? 0 : 1;
    passcode_fpga_reset_to_waiting(dev);
    return rc;
}

static int mock_change_passcode_once(passcode_fpga_t *dev, const char *log_path) {
    char input[5] = {0};

    if (reject_if_busy(dev, log_path, "mock_change_busy") != 0) {
        return 1;
    }

    passcode_fpga_send_command(dev, PASSCODE_CMD_CHANGE_PASSCODE);

    if (!mock_read_passcode_keys(dev, PASSCODE_STATUS_INPUT_CURRENT_PASSCODE, input) ||
        strcmp(input, dev->mock_regs.passcode) != 0) {
        dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_PASSCODE_CHANGE_FAIL, 4);
        print_status(dev);
        passcode_append_log(log_path, "mock_change", dev);
        passcode_fpga_reset_to_waiting(dev);
        return 1;
    }

    dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_INPUT_NEW_PASSCODE, 0);

    if (!mock_read_passcode_keys(dev, PASSCODE_STATUS_INPUT_NEW_PASSCODE, input)) {
        passcode_append_log(log_path, "mock_change", dev);
        passcode_fpga_reset_to_waiting(dev);
        return 1;
    }

    memcpy(dev->mock_regs.passcode, input, sizeof(dev->mock_regs.passcode));
    dev->mock_regs.status = passcode_make_status(PASSCODE_STATUS_PASSCODE_CHANGE_SUCCESS, 4);
    print_status(dev);
    passcode_append_log(log_path, "mock_change", dev);
    passcode_fpga_reset_to_waiting(dev);
    return 0;
}

static int mock_watch(passcode_fpga_t *dev, const char *log_path) {
    char input[32];

    print_status(dev);
    while (true) {
        if (!read_mock_line("mock command [a=auth, c=change, s=status, q=quit]: ",
                            input, sizeof(input))) {
            return 1;
        }

        if (strcmp(input, "a") == 0 || strcmp(input, "auth") == 0) {
            mock_authenticate_once(dev, log_path);
            print_status(dev);
        } else if (strcmp(input, "c") == 0 || strcmp(input, "change") == 0) {
            mock_change_passcode_once(dev, log_path);
            print_status(dev);
        } else if (strcmp(input, "s") == 0 || strcmp(input, "status") == 0) {
            print_status(dev);
        } else if (strcmp(input, "q") == 0 || strcmp(input, "quit") == 0) {
            return 0;
        } else {
            fprintf(stderr, "unknown mock command\n");
        }
    }
}
#endif

static int watch(passcode_fpga_t *dev, const char *log_path) {
#ifdef PASSCODE_ENABLE_MOCK
    if (dev->mock) {
        return mock_watch(dev, log_path);
    }
#endif

    uint32_t last_status = UINT32_MAX;

    while (true) {
        uint32_t status = passcode_fpga_read(dev, PASSCODE_REG_STATUS);

        /* Print only status changes so the terminal stays readable. */
        if (status != last_status) {
            print_status(dev);
            if (passcode_status_is_terminal(status)) {
                passcode_append_log(log_path, "status", dev);
                passcode_fpga_reset_to_waiting(dev);
            }
            last_status = status;
        }

        sleep_ms(50);
    }

    return 0;
}

static int authenticate_once(passcode_fpga_t *dev, const char *log_path) {
    uint32_t status = PASSCODE_STATUS_WAITING_COMMANDS;

#ifdef PASSCODE_ENABLE_MOCK
    if (dev->mock) {
        return mock_authenticate_once(dev, log_path);
    }
#endif

    /* This mirrors the PAM behavior: start FPGA auth, then wait for a result. */
    if (reject_if_busy(dev, log_path, "auth_busy") != 0) {
        return 1;
    }

    passcode_fpga_send_command(dev, PASSCODE_CMD_AUTH);

    if (wait_result_with_status_updates(dev, 30, 50, &status) != 0) {
        fprintf(stderr, "authentication timed out\n");
        passcode_append_log(log_path, "timeout", dev);
        return 1;
    }

    passcode_append_log(log_path, "auth", dev);
    passcode_fpga_reset_to_waiting(dev);
    return passcode_status_code(status) == PASSCODE_STATUS_AUTH_SUCCESS ? 0 : 1;
}

static int change_passcode_once(passcode_fpga_t *dev, const char *log_path) {
    uint32_t status = PASSCODE_STATUS_WAITING_COMMANDS;

#ifdef PASSCODE_ENABLE_MOCK
    if (dev->mock) {
        return mock_change_passcode_once(dev, log_path);
    }
#endif

    if (reject_if_busy(dev, log_path, "change_busy") != 0) {
        return 1;
    }

    passcode_fpga_send_command(dev, PASSCODE_CMD_CHANGE_PASSCODE);

    if (wait_result_with_status_updates(dev, 30, 50, &status) != 0) {
        fprintf(stderr, "passcode change timed out\n");
        passcode_append_log(log_path, "change_timeout", dev);
        return 1;
    }

    passcode_append_log(log_path, "change", dev);
    passcode_fpga_reset_to_waiting(dev);
    return passcode_status_code(status) == PASSCODE_STATUS_PASSCODE_CHANGE_SUCCESS ? 0 : 1;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);

    app_options_t options;
    if (parse_options(argc, argv, &options) != 0) {
        usage(argv[0]);
        return 2;
    }

    passcode_fpga_t dev;
    if (passcode_fpga_open(&dev, options.mock, PASSCODE_PIO_BASE) != 0) {
        perror("open FPGA bridge");
        return 1;
    }

    int rc = 0;
    if (strcmp(options.command, "start") == 0) {
        if (reject_if_busy(&dev, PASSCODE_CLI_LOG_PATH, "start_busy") != 0) {
            passcode_fpga_close(&dev);
            return 1;
        }
        passcode_fpga_send_command(&dev, PASSCODE_CMD_AUTH);
        print_status(&dev);
        passcode_append_log(PASSCODE_CLI_LOG_PATH, "start", &dev);
    } else if (strcmp(options.command, "auth") == 0) {
        rc = authenticate_once(&dev, PASSCODE_CLI_LOG_PATH);
    } else if (strcmp(options.command, "change") == 0) {
        rc = change_passcode_once(&dev, PASSCODE_CLI_LOG_PATH);
    } else if (strcmp(options.command, "watch") == 0) {
        rc = watch(&dev, PASSCODE_CLI_LOG_PATH);
    } else if (strcmp(options.command, "status") == 0) {
        print_status(&dev);
    } else {
        fprintf(stderr, "unknown command: %s\n", options.command);
        usage(argv[0]);
        rc = 2;
    }

    passcode_fpga_close(&dev);
    return rc;
}
