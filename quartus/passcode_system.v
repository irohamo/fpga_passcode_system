/*
 * Top wrapper that connects the passcode keypad core to two Avalon-MM PIO-style
 * registers for the HPS lightweight bridge.
 *
 * command_data:
 *   HPS writes 0, 1, or 2. The passcode core reads this as command.
 *
 * status_data:
 *   The passcode core continuously updates STATUS[7:0] and DIGITS[15:8].
 *   HPS reads this register from Linux.
 */

module passcode_system (
    input  wire        clk,
    input  wire        reset,
    input  wire        rst_n,

    input  wire [3:0]  row,
    output wire [3:0]  col,
    output wire [3:0]  led,

    input  wire [1:0]  command_address,
    input  wire        command_read,
    output wire [31:0] command_readdata,
    input  wire        command_write,
    input  wire [31:0] command_writedata,

    input  wire [1:0]  status_address,
    input  wire        status_read,
    output wire [31:0] status_readdata,
    input  wire        status_write,
    input  wire [31:0] status_writedata
);

    wire [31:0] command_data;
    wire [31:0] status_data;
    wire [4:0]  status_code;

    PasscodeCommandPIO command_pio (
        .reset(reset),
        .clk(clk),
        .address(command_address),
        .read(command_read),
        .readdata(command_readdata),
        .write(command_write),
        .writedata(command_writedata),
        .command(command_data)
    );

    passcode passcode_core (
        .clk(clk),
        .rst_n(rst_n),
        .command(command_data),
        .row(row),
        .col(col),
        .status(status_code),
        .status_raw(status_data),
        .led(led)
    );

    PasscodeStatusPIO status_pio (
        .reset(reset),
        .clk(clk),
        .address(status_address),
        .read(status_read),
        .readdata(status_readdata),
        .write(status_write),
        .writedata(status_writedata),
        .status_next(status_data),
        .status_we(1'b1),
        .status()
    );

endmodule

