/*
 * MyPIO-style command register.
 *
 * Linux writes COMMAND through Avalon-MM, and FPGA logic reads the command_out
 * conduit output.
 */

module command_pio (
    input  wire        reset,
    input  wire        clk,
    input  wire [1:0]  address,
    input  wire        read,
    output reg  [31:0] readdata,
    input  wire        write,
    input  wire [31:0] writedata,
    output wire [31:0] command_out
);

    reg [31:0] command_value;

    assign command_out = command_value;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            command_value <= 32'd0;
        end
        else if (write) begin
            case (address)
                2'b00: command_value <= writedata;
                default: command_value <= command_value;
            endcase
        end
    end

    always @* begin
        readdata = 32'd0;
        if (read) begin
            case (address)
                2'b00: readdata = command_value;
                default: readdata = 32'd0;
            endcase
        end
    end

endmodule
