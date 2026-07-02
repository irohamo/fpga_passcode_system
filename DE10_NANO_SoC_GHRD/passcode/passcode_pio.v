/*
 * Single-file Avalon-MM passcode component for Platform Designer.
 *
 * Register map:
 *   address 0: command register, HPS write/read
 *   address 1: status register, HPS read, optional debug write
 */

module passcode_pio (
    input  wire        clk,
    input  wire        reset,

    input  wire [3:0]  row,
    output wire [3:0]  col,
    output wire [3:0]  led,

    input  wire [1:0]  address,
    input  wire        read,
    output reg  [31:0] readdata,
    input  wire        write,
    input  wire [31:0] writedata
);

    localparam ADDR_COMMAND = 2'd0;
    localparam ADDR_STATUS  = 2'd1;

    reg  [31:0] command;
    reg  [31:0] status;
    wire [31:0] status_next;
    wire        core_rst_n;

    assign core_rst_n = ~reset;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            command <= 32'd0;
            status  <= 32'd0;
        end else begin
            status <= status_next;

            if (write) begin
                case (address)
                    ADDR_COMMAND: command <= writedata;
                    // Debug hook: normal Linux code should let FPGA own status.
                    ADDR_STATUS:  status <= writedata;
                    default: begin
                        command <= command;
                        status  <= status_next;
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

    password_core password_core_inst (
        .clk(clk),
        .rst_n(core_rst_n),
        .command(command),
        .row(row),
        .col(col),
        .status_raw(status_next),
        .led(led)
    );

endmodule

module password_core (
    input wire clk,
    input wire rst_n,
    input wire [31:0] command,

    input wire [3:0] row,
    output wire [3:0] col,

    output wire [31:0] status_raw,
    output reg [3:0] led
);

localparam CMD_NONE            = 32'd0;
localparam CMD_AUTH            = 32'd1;
localparam CMD_CHANGE_PASSWORD = 32'd2;

localparam WAITING_COMMANDS   = 4'd0;
localparam INPUT_PASSWORD     = 4'd1;
localparam AUTH_SUCCESS       = 4'd2;
localparam AUTH_FAIL          = 4'd3;
localparam CURRENT_PASSWORD   = 4'd4;
localparam CHANGE_NEWPASSWORD = 4'd5;
localparam CHANGE_SUCCESS     = 4'd6;
localparam CHANGE_FAIL        = 4'd7;
localparam PASSWORD_ERROR     = 4'd8;
localparam KEY_A    = 4'ha;
localparam KEY_C    = 4'hc;
localparam KEY_STAR = 4'he;
localparam KEY_B    = 4'hb;
localparam KEY_D    = 4'hd;

reg [3:0] stored_pwd0;
reg [3:0] stored_pwd1;
reg [3:0] stored_pwd2;
reg [3:0] stored_pwd3;

wire [3:0] key_code;
wire key_press;

reg [3:0] status;

reg [3:0] input_pwd0;
reg [3:0] input_pwd1;
reg [3:0] input_pwd2;
reg [3:0] input_pwd3;

reg [2:0] digit_count;

assign status_raw = {16'd0, 5'd0, digit_count, 4'd0, status};

keyboard_scan u_keyboard_scan (
    .clk       (clk),
    .rst_n     (rst_n),
    .scan_out  (col),
    .detect_in (row),
    .key_code  (key_code),
    .key_press (key_press)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stored_pwd0 <= 4'd1;
        stored_pwd1 <= 4'd2;
        stored_pwd2 <= 4'd3;
        stored_pwd3 <= 4'd4;

        input_pwd0 <= 4'd0;
        input_pwd1 <= 4'd0;
        input_pwd2 <= 4'd0;
        input_pwd3 <= 4'd0;

        digit_count <= 3'd0;
        status <= WAITING_COMMANDS;
    end
    else if (status == WAITING_COMMANDS) begin
        input_pwd0 <= 4'd0;
        input_pwd1 <= 4'd0;
        input_pwd2 <= 4'd0;
        input_pwd3 <= 4'd0;
        digit_count <= 3'd0;

        if (command == CMD_AUTH)
            status <= INPUT_PASSWORD;
        else if (command == CMD_CHANGE_PASSWORD)
            status <= CURRENT_PASSWORD;
    end
    else if ((status == AUTH_SUCCESS ||
              status == AUTH_FAIL ||
              status == CHANGE_SUCCESS ||
              status == CHANGE_FAIL ||
              status == PASSWORD_ERROR) &&
             command == CMD_NONE) begin
        input_pwd0 <= 4'd0;
        input_pwd1 <= 4'd0;
        input_pwd2 <= 4'd0;
        input_pwd3 <= 4'd0;
        digit_count <= 3'd0;
        status <= WAITING_COMMANDS;
    end
    else if (key_press) begin
        if (key_code == KEY_C || key_code == KEY_STAR) begin
            if (status == INPUT_PASSWORD ||
                status == CURRENT_PASSWORD ||
                status == CHANGE_NEWPASSWORD) begin
                input_pwd0 <= 4'd0;
                input_pwd1 <= 4'd0;
                input_pwd2 <= 4'd0;
                input_pwd3 <= 4'd0;
                digit_count <= 3'd0;
            end
        end else begin
            case (status)
                INPUT_PASSWORD: begin
                    if (key_code <= 4'd9) begin
                        if (digit_count < 3'd4) begin
                            case (digit_count)
                                3'd0: input_pwd0 <= key_code;
                                3'd1: input_pwd1 <= key_code;
                                3'd2: input_pwd2 <= key_code;
                                3'd3: input_pwd3 <= key_code;
                            endcase
                            digit_count <= digit_count + 1'b1;
                        end else begin
                            status <= PASSWORD_ERROR;
                        end
                    end else if (key_code == KEY_A) begin
                        if (digit_count == 3'd4) begin
                            if (input_pwd0 == stored_pwd0 &&
                                input_pwd1 == stored_pwd1 &&
                                input_pwd2 == stored_pwd2 &&
                                input_pwd3 == stored_pwd3)
                                status <= AUTH_SUCCESS;
                            else
                                status <= AUTH_FAIL;
                        end else if (digit_count > 3'd0) begin
                            status <= PASSWORD_ERROR;
                        end
                    end else if (key_code == KEY_B) begin
                        input_pwd0 <= 4'd0;
                        input_pwd1 <= 4'd0;
                        input_pwd2 <= 4'd0;
                        input_pwd3 <= 4'd0;
                        digit_count <= 3'd0;
                        status <= CURRENT_PASSWORD;
                    end else if (key_code == KEY_D) begin
                        if (digit_count > 3'd0) begin
                            case (digit_count)
                                3'd1: input_pwd0 <= 4'd0;
                                3'd2: input_pwd1 <= 4'd0;
                                3'd3: input_pwd2 <= 4'd0;
                                3'd4: input_pwd3 <= 4'd0;
                            endcase
                            digit_count <= digit_count - 1'b1;
                        end
                    end
                end

                CURRENT_PASSWORD: begin
                    if (key_code <= 4'd9) begin
                        if (digit_count < 3'd4) begin
                            case (digit_count)
                                3'd0: input_pwd0 <= key_code;
                                3'd1: input_pwd1 <= key_code;
                                3'd2: input_pwd2 <= key_code;
                                3'd3: input_pwd3 <= key_code;
                            endcase
                            digit_count <= digit_count + 1'b1;
                        end else begin
                            status <= PASSWORD_ERROR;
                        end
                    end else if (key_code == KEY_A) begin
                        if (digit_count == 3'd4) begin
                            if (input_pwd0 == stored_pwd0 &&
                                input_pwd1 == stored_pwd1 &&
                                input_pwd2 == stored_pwd2 &&
                                input_pwd3 == stored_pwd3)
                                status <= CHANGE_NEWPASSWORD;
                            else
                                status <= CHANGE_FAIL;

                            input_pwd0 <= 4'd0;
                            input_pwd1 <= 4'd0;
                            input_pwd2 <= 4'd0;
                            input_pwd3 <= 4'd0;
                            digit_count <= 3'd0;
                        end else begin
                            status <= PASSWORD_ERROR;
                        end
                    end
                end

                CHANGE_NEWPASSWORD: begin
                    if (key_code <= 4'd9) begin
                        if (digit_count < 3'd4) begin
                            case (digit_count)
                                3'd0: input_pwd0 <= key_code;
                                3'd1: input_pwd1 <= key_code;
                                3'd2: input_pwd2 <= key_code;
                                3'd3: input_pwd3 <= key_code;
                            endcase
                            digit_count <= digit_count + 1'b1;
                        end else begin
                            status <= PASSWORD_ERROR;
                        end
                    end else if (key_code == KEY_A) begin
                        if (digit_count == 3'd4) begin
                            stored_pwd0 <= input_pwd0;
                            stored_pwd1 <= input_pwd1;
                            stored_pwd2 <= input_pwd2;
                            stored_pwd3 <= input_pwd3;

                            input_pwd0 <= 4'd0;
                            input_pwd1 <= 4'd0;
                            input_pwd2 <= 4'd0;
                            input_pwd3 <= 4'd0;
                            status <= CHANGE_SUCCESS;
                        end else begin
                            status <= PASSWORD_ERROR;
                        end
                    end
                end

                AUTH_SUCCESS,
                AUTH_FAIL,
                CHANGE_SUCCESS,
                CHANGE_FAIL,
                PASSWORD_ERROR: begin
                end

                default: begin
                    status <= WAITING_COMMANDS;
                end
            endcase
        end
    end
end

always @(*) begin
    case (status)
        WAITING_COMMANDS:   led = 4'b0000;
        INPUT_PASSWORD:     led = 4'b0001;
        AUTH_SUCCESS:       led = 4'b1111;
        AUTH_FAIL:          led = 4'b0011;
        CURRENT_PASSWORD:   led = 4'b1000;
        CHANGE_NEWPASSWORD: led = 4'b1100;
        CHANGE_SUCCESS:     led = 4'b1010;
        CHANGE_FAIL:        led = 4'b0110;
        PASSWORD_ERROR:     led = 4'b1001;
        default:            led = 4'b0000;
    endcase
end

endmodule

module keyboard_scan (
    input  wire       clk,
    input  wire       rst_n,

    output reg  [3:0] scan_out,
    input  wire [3:0] detect_in,

    output reg  [3:0] key_code,
    output reg        key_press
);

    localparam integer CLK_HZ          = 50000000;
    localparam integer SCAN_HZ         = 1000;
    localparam integer SCAN_DIV        = CLK_HZ / SCAN_HZ;
    localparam [7:0]   DEBOUNCE_FRAMES = 8'd5;

    reg [31:0] scan_cnt;
    reg [1:0]  scan_col;

    reg        raw_down;
    reg [3:0]  raw_code;

    reg        frame_down;
    reg [3:0]  frame_code;
    reg        frame_multi;

    reg        accum_down;
    reg [3:0]  accum_code;
    reg        accum_multi;

    reg        stable_down;
    reg [3:0]  stable_code;
    reg [7:0]  stable_cnt;

    reg        debounced_down;
    reg [3:0]  debounced_code;
    reg        debounced_down_d;

    always @(*) begin
        case (scan_col)
            2'd0: scan_out = 4'b1110;
            2'd1: scan_out = 4'b1101;
            2'd2: scan_out = 4'b1011;
            default: scan_out = 4'b0111;
        endcase
    end

    always @(*) begin
        raw_down = 1'b1;
        raw_code = 4'h0;

        case ({scan_col, detect_in})
            {2'd0, 4'b1110}: raw_code = 4'd1;
            {2'd1, 4'b1110}: raw_code = 4'd2;
            {2'd2, 4'b1110}: raw_code = 4'd3;
            {2'd3, 4'b1110}: raw_code = 4'ha;

            {2'd0, 4'b1101}: raw_code = 4'd4;
            {2'd1, 4'b1101}: raw_code = 4'd5;
            {2'd2, 4'b1101}: raw_code = 4'd6;
            {2'd3, 4'b1101}: raw_code = 4'hb;

            {2'd0, 4'b1011}: raw_code = 4'd7;
            {2'd1, 4'b1011}: raw_code = 4'd8;
            {2'd2, 4'b1011}: raw_code = 4'd9;
            {2'd3, 4'b1011}: raw_code = 4'hc;

            {2'd0, 4'b0111}: raw_code = 4'he;
            {2'd1, 4'b0111}: raw_code = 4'd0;
            {2'd2, 4'b0111}: raw_code = 4'hf;
            {2'd3, 4'b0111}: raw_code = 4'hd;

            default: begin
                raw_down = 1'b0;
                raw_code = 4'h0;
            end
        endcase
    end

    always @(*) begin
        accum_down  = frame_down | raw_down;
        accum_code  = raw_down ? raw_code : frame_code;
        accum_multi = frame_multi | (frame_down & raw_down & (raw_code != frame_code));
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt         <= 32'd0;
            scan_col         <= 2'd0;
            frame_down       <= 1'b0;
            frame_code       <= 4'h0;
            frame_multi      <= 1'b0;
            stable_down      <= 1'b0;
            stable_code      <= 4'h0;
            stable_cnt       <= 8'd0;
            debounced_down   <= 1'b0;
            debounced_code   <= 4'h0;
            debounced_down_d <= 1'b0;
            key_code         <= 4'h0;
            key_press        <= 1'b0;
        end else begin
            key_press <= 1'b0;
            debounced_down_d <= debounced_down;

            if (scan_cnt == SCAN_DIV - 1) begin
                scan_cnt <= 32'd0;
                scan_col <= scan_col + 2'd1;

                if (scan_col == 2'd3) begin
                    if (((accum_down & !accum_multi) == stable_down) &&
                        (!(accum_down & !accum_multi) || (accum_code == stable_code))) begin
                        if (stable_cnt < DEBOUNCE_FRAMES)
                            stable_cnt <= stable_cnt + 8'd1;
                    end else begin
                        stable_down <= accum_down & !accum_multi;
                        stable_code <= accum_multi ? 4'h0 : accum_code;
                        stable_cnt  <= 8'd0;
                    end

                    if (stable_cnt >= DEBOUNCE_FRAMES) begin
                        debounced_down <= stable_down;
                        debounced_code <= stable_code;
                    end

                    frame_down  <= 1'b0;
                    frame_code  <= 4'h0;
                    frame_multi <= 1'b0;
                end else begin
                    frame_down  <= accum_down;
                    frame_code  <= accum_code;
                    frame_multi <= accum_multi;
                end
            end else begin
                scan_cnt <= scan_cnt + 32'd1;
            end

            if (debounced_down && !debounced_down_d) begin
                key_press <= 1'b1;
                key_code  <= debounced_code;
            end
        end
    end

endmodule
