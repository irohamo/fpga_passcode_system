#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

// Physical address of lightweight HPS-to-FPGA bridge
#define HW_REGS_BASE   0x????????
#define HW_REGS_SPAN   0x????????

// These offsets must be changed according to your Platform Designer address map
#define CMD_OFFSET     0x????   // Linux -> FPGA command register
#define STATUS_OFFSET  0x???   // FPGA -> Linux status register

// Linux command
#define CMD_START      1        // Start passcode system

// FPGA status
#define IDLE                       0
#define STATUS_INPUT_PASSCODE      1   // Waiting for passcode input
#define STATUS_AUTH_SUCCESS        2   // Passcode correct
#define STATUS_AUTH_FAIL           3   // Passcode incorrect
#define STATUS_CHANGE_MODE         4   // Passcode change mode
#define STATUS_CHANGE_SUCCESS      5   // Passcode changed successfully
#define STATUS_CHANGE_FAIL         6   // Passcode change failed
#define STATUS_PASSCODE_TOO_LONG   7   // More than 4 digits entered

int main(void)
{
    int fd;
    void *virtual_base;

    volatile uint32_t *cmd_reg;
    volatile uint32_t *status_reg;

    uint32_t status;
    uint32_t last_status = 0;


     //Open /dev/mem to access FPGA registers from Linux user space.
    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem failed");
        return 1;
    }

     //Map FPGA physical address space to Linux virtual address space.
    virtual_base = mmap(NULL,
                        HW_REGS_SPAN,
                        PROT_READ | PROT_WRITE,
                        MAP_SHARED,
                        fd,
                        HW_REGS_BASE);

    if (virtual_base == MAP_FAILED) {
        perror("mmap failed");
        close(fd);
        return 1;
    }

    //Register pointers

    cmd_reg = (volatile uint32_t *)((uint8_t *)virtual_base + CMD_OFFSET);
    status_reg = (volatile uint32_t *)((uint8_t *)virtual_base + STATUS_OFFSET);

    printf("Passcode Lock System Start\n");
    printf("----------------------------------\n");

    
     // Send start command to FPGA.
     //After this, all keypad operations are handled by FPGA.
    *cmd_reg = CMD_START;

    while (1) {
        status = *status_reg;

        if (status != last_status) {
            switch (status) {

                case IDLE:

                 printf("waiting\n")

                 sleep
                case STATUS_INPUT_PASSCODE:
                    printf("\nPlease enter your passcode on the FPGA keypad.\n");
                    printf("A: Confirm passcode\n");
                    printf("B: Change passcode\n");
                    printf("C: Clear input\n");
                    printf("D: Backspace\n");
                    break;

                case STATUS_AUTH_SUCCESS:
                    printf("\nAuthentication successful.\n");
                    printf("Returning to passcode input mode...\n");
                    sleep (5000)
                    break;

                case STATUS_AUTH_FAIL:
                    printf("\nAuthentication failed.\n");
                    printf("Returning to passcode input mode...\n");
                    break;

                case STATUS_CHANGE_MODE:
                    printf("\nPasscode change mode.\n");
                    printf("Please enter a new passcode on the FPGA keypad.\n");
                    printf("Press A to confirm the new passcode.\n");
                    break;

                case STATUS_CHANGE_SUCCESS:
                    printf("\nPasscode changed successfully.\n");
                    printf("Returning to passcode input mode...\n");
                    break;

                case STATUS_CHANGE_FAIL:
                    printf("\nPasscode change failed.\n");
                    printf("Returning to passcode input mode...\n");
                    break;

                case STATUS_PASSCODE_TOO_LONG:
                    printf("\nError: Please enter a passcode within 4 digits.\n");
                    break;

                default:
                    break;
            }

            last_status = status;
        }

        usleep(50000);   // wait 50 ms
    }

    munmap(virtual_base, HW_REGS_SPAN);
    close(fd);

    return 0;
}