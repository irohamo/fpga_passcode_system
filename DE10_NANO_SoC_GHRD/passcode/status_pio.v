/*
 * MyPIO-style status register.
 *
 * FPGA logic drives status_next, and Linux reads STATUS through Avalon-MM.
 * A write path is kept for simple manual debug tests.
 */

module status_pio (
    input  wire        reset,
    input  wire        clk,
    input  wire [1:0]  address,
    input  wire        read,
    output reg  [31:0] readdata,
    input  wire        write,
    input  wire [31:0] writedata,
    input  wire [31:0] status_next
);

    reg [31:0] status;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            status <= 32'd0;
        end
        else begin
            status <= status_next;

            if (write) begin
                case (address)
                    2'b00: status <= writedata;
                    default: status <= status_next;
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
