module passcode (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [3:0]  row,   // 
    output reg  [3:0]  col,   // 

    output reg  [4:0]  status,
    output reg  [3:0]  led
);

    // status
    localparam INPUT_PASSCODE     = 5'd1;
    localparam AUTH_SUCCESS       = 5'd2;
    localparam AUTH_FAIL          = 5'd3;
    localparam CURRENT_PASSCODE   = 5'd4;
    localparam CHANGE_NEWPASSCODE = 5'd5;
    localparam CHANGE_SUCCESS     = 5'd6;
    localparam CHANGE_FAIL        = 5'd7;
    localparam PASSCODE_ERROR     = 5'd8;

    // key
    localparam KEY_A    = 4'ha;
    localparam KEY_B    = 4'hb;
    localparam KEY_C    = 4'hc;
    localparam KEY_D    = 4'hd;
    localparam KEY_STAR = 4'he;
    localparam KEY_HASH = 4'hf;

    reg [15:0] stored_passcode;
    reg [15:0] input_passcode;
    reg [2:0]  digit_count;

    reg [3:0] key_value;
    reg       key_valid;

    // scan
    reg [1:0]  scan_col;
    reg [19:0] scan_cnt;
    reg [21:0] debounce_cnt;

    reg [3:0] row_save;
    reg [3:0] col_save;

    reg [2:0] key_state;

    localparam SCAN         = 3'd0;
    localparam DEBOUNCE     = 3'd1;
    localparam OUTPUT_KEY   = 3'd2;
    localparam WAIT_RELEASE = 3'd3;

    // =========================
    // Keypad scan + debounce
    // =========================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_col     <= 2'd0;
            scan_cnt     <= 20'd0;
            debounce_cnt <= 22'd0;

            col          <= 4'b1110;
            row_save     <= 4'b1111;
            col_save     <= 4'b1110;

            key_value    <= 4'h0;
            key_valid    <= 1'b0;
            key_state    <= SCAN;
        end else begin
            key_valid <= 1'b0;

            case (key_state)

                // 
                SCAN: begin
                    if (scan_cnt >= 20'd50000) begin
                        scan_cnt <= 20'd0;

                        case (scan_col)
                            2'd0: col <= 4'b1110;
                            2'd1: col <= 4'b1101;
                            2'd2: col <= 4'b1011;
                            2'd3: col <= 4'b0111;
                        endcase

                        scan_col <= scan_col + 1'b1;
                    end else begin
                        scan_cnt <= scan_cnt + 1'b1;
                    end

                    if (row != 4'b1111) begin
                        row_save <= row;
                        col_save <= col;
                        debounce_cnt <= 22'd0;
                        key_state <= DEBOUNCE;
                    end
                end

                // 20ms 
                DEBOUNCE: begin
                    if (debounce_cnt >= 22'd1000000) begin
                        if (row != 4'b1111) begin
                            row_save <= row;
                            key_state <= OUTPUT_KEY;
                        end else begin
                            key_state <= SCAN;
                        end
                    end else begin
                        debounce_cnt <= debounce_cnt + 1'b1;
                    end
                end

                // output key_valid
                OUTPUT_KEY: begin
                    case ({col_save, row_save})
                        8'b1110_1110: key_value <= 4'd1;
                        8'b1101_1110: key_value <= 4'd2;
                        8'b1011_1110: key_value <= 4'd3;
                        8'b0111_1110: key_value <= KEY_A;

                        8'b1110_1101: key_value <= 4'd4;
                        8'b1101_1101: key_value <= 4'd5;
                        8'b1011_1101: key_value <= 4'd6;
                        8'b0111_1101: key_value <= KEY_B;

                        8'b1110_1011: key_value <= 4'd7;
                        8'b1101_1011: key_value <= 4'd8;
                        8'b1011_1011: key_value <= 4'd9;
                        8'b0111_1011: key_value <= KEY_C;

                        8'b1110_0111: key_value <= KEY_STAR;
                        8'b1101_0111: key_value <= 4'd0;
                        8'b1011_0111: key_value <= KEY_HASH;
                        8'b0111_0111: key_value <= KEY_D;

                        default: key_value <= 4'h0;
                    endcase

                    key_valid <= 1'b1;
                    key_state <= WAIT_RELEASE;
                end

                // 等待松开
                WAIT_RELEASE: begin
                    col <= 4'b0000;

                    if (row == 4'b1111) begin
                        col <= 4'b1110;
                        scan_col <= 2'd0;
                        key_state <= SCAN;
                    end
                end

                default: begin
                    key_state <= SCAN;
                end

            endcase
        end
    end

    // =========================
    // Passcode control
    // =========================
    always @(posedge clk or negedge rst_n) begin
	 led<= key_value;//keyvalue test  
        if (!rst_n) begin
            stored_passcode <= 16'd1234;
            input_passcode  <= 16'd0;
            digit_count     <= 3'd0;
            status          <= INPUT_PASSCODE;
        end else begin
            if (key_valid) begin

                // * / C：clear
                if (key_value == KEY_STAR || key_value == KEY_C) begin
                    input_passcode <= 16'd0;
                    digit_count <= 3'd0;
                    status <= INPUT_PASSCODE;
                end

                // input number
                else if (key_value <= 4'd9) begin
                    if (status == INPUT_PASSCODE ||
                        status == CURRENT_PASSCODE ||
                        status == CHANGE_NEWPASSCODE) begin

                        if (digit_count < 4) begin
                            input_passcode <= input_passcode * 10 + key_value;
                            digit_count <= digit_count + 1'b1;
                        end else begin
                            status <= PASSCODE_ERROR;
                        end
                    end
                end

                // A：confirm
                else if (key_value == KEY_A) begin
                    if (status == INPUT_PASSCODE) begin
                        if (digit_count == 4) begin
                            if (input_passcode == stored_passcode)
                                status <= AUTH_SUCCESS;
                            else
                                status <= AUTH_FAIL;
                        end else begin
                            status <= PASSCODE_ERROR;
                        end

                        input_passcode <= 16'd0;
                        digit_count <= 3'd0;
                    end

                    else if (status == CURRENT_PASSCODE) begin
                        if (digit_count == 4) begin
                            if (input_passcode == stored_passcode)
                                status <= CHANGE_NEWPASSCODE;
                            else
                                status <= CHANGE_FAIL;
                        end else begin
                            status <= PASSCODE_ERROR;
                        end

                        input_passcode <= 16'd0;
                        digit_count <= 3'd0;
                    end

                    else if (status == CHANGE_NEWPASSCODE) begin
                        if (digit_count == 4) begin
                            stored_passcode <= input_passcode;
                            status <= CHANGE_SUCCESS;
                        end else begin
                            status <= PASSCODE_ERROR;
                        end

                        input_passcode <= 16'd0;
                        digit_count <= 3'd0;
                    end
                end

                // B：change passcode
                else if (key_value == KEY_B) begin
                    status <= CURRENT_PASSCODE;
                    input_passcode <= 16'd0;
                    digit_count <= 3'd0;
                end

                // D：backspace
                else if (key_value == KEY_D) begin
                    if (digit_count > 0) begin
                        input_passcode <= input_passcode / 10;
                        digit_count <= digit_count - 1'b1;
                    end
                end
            end
        end
    end

    // =========================
    // LED display
    // =========================
   /* always @(*) begin
        case (status)
            INPUT_PASSCODE:     led = 4'b0001;
            AUTH_SUCCESS:       led = 4'b1111;
            AUTH_FAIL:          led = 4'b0011;
            CURRENT_PASSCODE:   led = 4'b1000;
            CHANGE_NEWPASSCODE: led = 4'b1100;
            CHANGE_SUCCESS:     led = 4'b1010;
            CHANGE_FAIL:        led = 4'b0110;
            PASSCODE_ERROR:     led = 4'b1001;
            default:            led = 4'b0000;
        endcase
    end
*/
endmodule