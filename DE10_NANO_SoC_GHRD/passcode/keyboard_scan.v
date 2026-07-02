module keyboard_scan (
    input  wire       clk,
    input  wire       rst_n,

    output reg  [3:0] scan_out,
    input  wire [3:0] detect_in,

    output reg  [3:0] key_code,
    output reg        key_press
);

    // 50 MHz clock assumed on DE10-Nano.
    // Scan one column every 1 ms, then debounce complete 4-column frames.
    localparam integer CLK_HZ         = 50000000;
    localparam integer SCAN_HZ        = 1000;
    localparam integer SCAN_DIV       = CLK_HZ / SCAN_HZ;
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

            {2'd0, 4'b0111}: raw_code = 4'he; // *
            {2'd1, 4'b0111}: raw_code = 4'd0;
            {2'd2, 4'b0111}: raw_code = 4'hf; // #
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