module password(
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
localparam KEY_B = 4'hb;
localparam KEY_D = 4'hd;

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
    if(!rst_n) begin
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
    else if(status == WAITING_COMMANDS) begin
        input_pwd0 <= 4'd0;
        input_pwd1 <= 4'd0;
        input_pwd2 <= 4'd0;
        input_pwd3 <= 4'd0;
        digit_count <= 3'd0;

        if(command == CMD_AUTH)
            status <= INPUT_PASSWORD;
        else if(command == CMD_CHANGE_PASSWORD)
            status <= CURRENT_PASSWORD;
    end
    else if((status == AUTH_SUCCESS ||
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
    else if(key_press) begin

        // C or *: clear current input while staying in the current input state.
        if(key_code == KEY_C || key_code == KEY_STAR) begin
            if(status == INPUT_PASSWORD ||
               status == CURRENT_PASSWORD ||
               status == CHANGE_NEWPASSWORD) begin
                input_pwd0 <= 4'd0;
                input_pwd1 <= 4'd0;
                input_pwd2 <= 4'd0;
                input_pwd3 <= 4'd0;
                digit_count <= 3'd0;
            end
        end

        else begin
            case(status)

                INPUT_PASSWORD: begin
                    if(key_code <= 4'd9) begin
                        if(digit_count < 3'd4) begin
                            case(digit_count)
                                3'd0: input_pwd0 <= key_code;
                                3'd1: input_pwd1 <= key_code;
                                3'd2: input_pwd2 <= key_code;
                                3'd3: input_pwd3 <= key_code;
                            endcase

                            digit_count <= digit_count + 1'b1;
                        end
                        else begin
                            status <= PASSWORD_ERROR;
                        end
                    end

                    else if(key_code == KEY_A) begin
                        if(digit_count == 3'd4) begin
                            if(input_pwd0 == stored_pwd0 &&
                               input_pwd1 == stored_pwd1 &&
                               input_pwd2 == stored_pwd2 &&
                               input_pwd3 == stored_pwd3)
                                status <= AUTH_SUCCESS;
                            else
                                status <= AUTH_FAIL;

                            // Keep digit_count at 4 until Linux acknowledges
                            // the terminal result with command=0.
                        end
                        else if(digit_count > 3'd0) begin
                            status <= PASSWORD_ERROR;
                        end
                    end

                    else if(key_code == KEY_B) begin
                        input_pwd0 <= 4'd0;
                        input_pwd1 <= 4'd0;
                        input_pwd2 <= 4'd0;
                        input_pwd3 <= 4'd0;

                        digit_count <= 3'd0;
                        status <= CURRENT_PASSWORD;
                    end

                    else if(key_code == KEY_D) begin
                        if(digit_count > 3'd0) begin
                            case(digit_count)
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
                    if(key_code <= 4'd9) begin
                        if(digit_count < 3'd4) begin
                            case(digit_count)
                                3'd0: input_pwd0 <= key_code;
                                3'd1: input_pwd1 <= key_code;
                                3'd2: input_pwd2 <= key_code;
                                3'd3: input_pwd3 <= key_code;
                            endcase

                            digit_count <= digit_count + 1'b1;
                        end
                        else begin
                            status <= PASSWORD_ERROR;
                        end
                    end

                    else if(key_code == KEY_A) begin
                        if(digit_count == 3'd4) begin
                            if(input_pwd0 == stored_pwd0 &&
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
                        end
                        else begin
                            status <= PASSWORD_ERROR;
                        end
                    end
                end

                CHANGE_NEWPASSWORD: begin
                    if(key_code <= 4'd9) begin
                        if(digit_count < 3'd4) begin
                            case(digit_count)
                                3'd0: input_pwd0 <= key_code;
                                3'd1: input_pwd1 <= key_code;
                                3'd2: input_pwd2 <= key_code;
                                3'd3: input_pwd3 <= key_code;
                            endcase

                            digit_count <= digit_count + 1'b1;
                        end
                        else begin
                            status <= PASSWORD_ERROR;
                        end
                    end

                    else if(key_code == KEY_A) begin
                        if(digit_count == 3'd4) begin
                            stored_pwd0 <= input_pwd0;
                            stored_pwd1 <= input_pwd1;
                            stored_pwd2 <= input_pwd2;
                            stored_pwd3 <= input_pwd3;

                            input_pwd0 <= 4'd0;
                            input_pwd1 <= 4'd0;
                            input_pwd2 <= 4'd0;
                            input_pwd3 <= 4'd0;

                            // Keep digit_count at 4 until Linux acknowledges
                            // the terminal result with command=0.
                            status <= CHANGE_SUCCESS;
                        end
                        else begin
                            status <= PASSWORD_ERROR;
                        end
                    end
                end

                AUTH_SUCCESS,
                AUTH_FAIL,
                CHANGE_SUCCESS,
                CHANGE_FAIL,
                PASSWORD_ERROR: begin
                    // Terminal states wait for Linux to acknowledge with command=0.
                end

                default: begin
                    status <= WAITING_COMMANDS;
                end

            endcase
        end
    end
end

always @(*) begin
    case(status)
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
