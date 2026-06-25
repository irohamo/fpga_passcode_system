CC ?= gcc
CFLAGS ?= -std=c11 -Wall -Wextra -O2
CPPFLAGS ?= -Isrc
LDFLAGS ?=
PAM_LIBDIR ?= /lib/security

BUILD_DIR := build
TARGET := $(BUILD_DIR)/passcodectl
MOCK_TARGET := $(BUILD_DIR)/passcodectl_mock
PAM_TARGET := $(BUILD_DIR)/pam_passcode.so
PAM_MOCK_TARGET := $(BUILD_DIR)/pam_passcode_mock.so
PAM_TEST_TARGET := $(BUILD_DIR)/pam_test
COMMON_SOURCES := src/passcode_fpga.c
CLI_SOURCES := src/passcodectl.c $(COMMON_SOURCES)
PAM_SOURCES := src/pam_passcode.c $(COMMON_SOURCES)
PAM_TEST_SOURCES := src/pam_test.c
CLI_OBJECTS := $(CLI_SOURCES:src/%.c=$(BUILD_DIR)/%.o)
CLI_MOCK_OBJECTS := $(CLI_SOURCES:src/%.c=$(BUILD_DIR)/%.mock.o)
PAM_OBJECTS := $(PAM_SOURCES:src/%.c=$(BUILD_DIR)/%.pam.o)
PAM_MOCK_OBJECTS := $(PAM_SOURCES:src/%.c=$(BUILD_DIR)/%.pam_mock.o)
PAM_TEST_OBJECTS := $(PAM_TEST_SOURCES:src/%.c=$(BUILD_DIR)/%.o)

.PHONY: all mock pam pam-mock pam-test install-pam install-pam-mock clean fclean re

all: $(TARGET)

mock: $(MOCK_TARGET)

pam: $(PAM_TARGET)

pam-mock: $(PAM_MOCK_TARGET)

pam-test: $(PAM_TEST_TARGET)

$(TARGET): $(CLI_OBJECTS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $(CLI_OBJECTS) $(LDFLAGS)

$(MOCK_TARGET): $(CLI_MOCK_OBJECTS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $(CLI_MOCK_OBJECTS) $(LDFLAGS)

$(PAM_TARGET): $(PAM_OBJECTS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -shared -o $@ $(PAM_OBJECTS) -lpam

$(PAM_MOCK_TARGET): $(PAM_MOCK_OBJECTS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -shared -o $@ $(PAM_MOCK_OBJECTS) -lpam

$(PAM_TEST_TARGET): $(PAM_TEST_OBJECTS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $(PAM_TEST_OBJECTS) -lpam

$(BUILD_DIR)/%.o: src/%.c src/passcode_protocol.h src/passcode_fpga.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR)/%.mock.o: src/%.c src/passcode_protocol.h src/passcode_fpga.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -DPASSCODE_ENABLE_MOCK -c -o $@ $<

$(BUILD_DIR)/%.pam.o: src/%.c src/passcode_protocol.h src/passcode_fpga.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -fPIC -c -o $@ $<

$(BUILD_DIR)/%.pam_mock.o: src/%.c src/passcode_protocol.h src/passcode_fpga.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -DPASSCODE_ENABLE_MOCK -fPIC -c -o $@ $<

install-pam: $(PAM_TARGET)
	install -m 0644 $(PAM_TARGET) $(PAM_LIBDIR)/pam_passcode.so

install-pam-mock: $(PAM_MOCK_TARGET)
	install -m 0644 $(PAM_MOCK_TARGET) $(PAM_LIBDIR)/pam_passcode_mock.so

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -f $(BUILD_DIR)/*.o

fclean: clean
	rm -f $(TARGET) $(MOCK_TARGET) $(PAM_TARGET) $(PAM_MOCK_TARGET) $(PAM_TEST_TARGET)
	rmdir $(BUILD_DIR) 2>/dev/null || true

re: fclean all
