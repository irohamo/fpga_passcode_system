/*
 * Avalon-MM PIO-style registers for Linux/HPS communication.
 *
 * COMMAND: Linux writes command values, FPGA logic reads them.
 * STATUS : FPGA logic writes status_raw, Linux reads it.
 */

module PasswordCommandPIO (
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
        end else if (write) begin
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

module PasswordStatusPIO (
    input  wire        reset,
    input  wire        clk,
    input  wire [1:0]  address,
    input  wire        read,
    output reg  [31:0] readdata,
    input  wire        write,
    input  wire [31:0] writedata,
    input  wire [31:0] status_next,
    input  wire        status_we,
    output reg  [31:0] status
);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            status <= 32'd0;
        end else begin
            if (status_we) begin
                status <= status_next;
            end

            // Optional HPS write support is useful for manual debugging.
            if (write) begin
                case (address)
                    2'b00: status <= writedata;
                    default: status <= status;
                endcase
            end
        end
    end

    always @* begin
        readdata = 32'd0;
        if (read) begin
            case (address)
                2'b00: readdata = status;
                default: readdata = 32'd0;
            endcase
        end
    end

endmodule

