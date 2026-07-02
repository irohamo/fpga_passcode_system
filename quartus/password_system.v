/*
 * Wrapper for connecting the keypad password core to HPS-visible registers.
 *
 * Platform Designer can expose the command_* and status_* Avalon-MM slave
 * ports to the HPS lightweight bridge.
 */

module password_system (
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

    PasswordCommandPIO command_pio (
        .reset(reset),
        .clk(clk),
        .address(command_address),
        .read(command_read),
        .readdata(command_readdata),
        .write(command_write),
        .writedata(command_writedata),
        .command(command_data)
    );

    password password_core (
        .clk(clk),
        .rst_n(rst_n),
        .command(command_data),
        .row(row),
        .col(col),
        .status_raw(status_data),
        .led(led)
    );

    PasswordStatusPIO status_pio (
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

