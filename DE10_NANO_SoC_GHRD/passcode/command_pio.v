/*
 * MyPIO-style command register.
 *
 * Linux writes COMMAND through Avalon-MM, and FPGA logic reads the command
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
    output reg  [31:0] command
);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            command <= 32'd0;
        end
        else if (write) begin
            case (address)
                2'b00: command <= writedata;
                default: command <= command;
            endcase
        end
    end

    always @* begin
        readdata = 32'd0;
        if (read) begin
            case (address)
                2'b00: readdata = command;
                default: readdata = 32'd0;
            endcase
        end
    end

endmodule
