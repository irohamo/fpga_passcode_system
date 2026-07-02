/*
 * MyPIO-style Avalon-MM register block for passcode control.
 *
 * address 0: COMMAND register, HPS write/read
 * address 1: STATUS register, HPS read, optional debug write
 *
 * This module is only the HPS-facing PIO part. Keep the Platform Designer
 * component simple: Avalon-MM signals only, with no extra conduit ports.
 */

module passcode_pio (
    input  wire        reset,
    input  wire        clk,
    input  wire [1:0]  address,
    input  wire        read,
    output reg  [31:0] readdata,
    input  wire        write,
    input  wire [31:0] writedata
);

    localparam ADDR_COMMAND = 2'b00;
    localparam ADDR_STATUS  = 2'b01;

    reg [31:0] command;
    reg [31:0] status;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            command <= 32'd0;
            status  <= 32'd0;
        end
        else begin
            if (write) begin
                case (address)
                    ADDR_COMMAND: command <= writedata;
                    ADDR_STATUS:  status <= writedata;
                    default: begin
                        command <= command;
                        status  <= status;
                    end
                endcase
            end
        end
    end

    always @* begin
        readdata = 32'd0;
        if (read) begin
            case (address)
                ADDR_COMMAND: readdata = command;
                ADDR_STATUS:  readdata = status;
                default:      readdata = 32'd0;
            endcase
        end
    end

endmodule
