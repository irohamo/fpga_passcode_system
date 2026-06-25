module keyboard(
    input clk,          // 50MHz时钟
    input rst_n,        // 复位（低有效）
    output reg [3:0] row,  // 行输出（扫描信号）
    input [3:0] col,     // 列输入（按键状态）
    output reg [3:0] key_code,  // 按键编码（0-9:数字，A:确认，B:取消，C:改密，D:退格）
    output reg key_press  // 按键有效标志
);

// 消抖计数器（20ms@50MHz：50M×0.02=1M个周期，取20位计数器）
reg [19:0] debounce_cnt;
reg [3:0] col_reg1, col_reg2;  // 列信号打拍（边沿检测）
wire col_pos_edge;  // 列信号上升沿（按键按下）
wire col_neg_edge;  // 列信号下降沿（按键释放）

// 行扫描状态机（4行循环扫描）
reg [1:0] scan_state;  // 0-3:当前扫描行
reg [3:0] key_map [0:15];  // 按键映射表（行列→编码）

// 初始化按键映射（0-9:0-9，A:确认(10), B:取消(11), C:改密(12), D:退格(13)）
initial begin
    key_map[0] = 4'd1; key_map[1] = 4'd2; key_map[2] = 4'd3; key_map[3] = 4'd10;  // 行0:1,2,3,确认(A)
    key_map[4] = 4'd4; key_map[5] = 4'd5; key_map[6] = 4'd6; key_map[7] = 4'd11;  // 行1:4,5,6,取消(B)
    key_map[8] = 4'd7; key_map[9] = 4'd8; key_map[10] = 4'd9; key_map[11] = 4'd12; // 行2:7,8,9,改密(C)
    key_map[12] = 4'd14; key_map[13] = 4'd0; key_map[14] = 4'd15; key_map[15] = 4'd13; // 行3:*,0,#,退格(D)（*用14，#用15占位）
end

// 列信号边沿检测
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        col_reg1 <= 4'b1111;
        col_reg2 <= 4'b1111;
    end else begin
        col_reg1 <= col;
        col_reg2 <= col_reg1;
    end
end
assign col_pos_edge = (col_reg1 != col_reg2) & (col_reg2 == 4'b1111);  // 下降沿（按键按下，列从高到低）
assign col_neg_edge = (col_reg1 != col_reg2) & (col_reg1 == 4'b1111);  // 上升沿（按键释放，列从低到高）

// 行扫描与消抖
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        row <= 4'b1110;  // 初始扫描第0行（低有效）
        scan_state <= 2'd0;
        debounce_cnt <= 20'd0;
        key_press <= 1'b0;
        key_code <= 4'd0;
    end else begin
        // 行扫描（每1ms切换一行，4行共4ms周期）
        if (debounce_cnt == 20'd49999) begin  // 1ms@50MHz（50M×0.001=5e4，取49999）
            debounce_cnt <= 20'd0;
            scan_state <= scan_state + 1'b1;
            case (scan_state)
                2'd0: row <= 4'b1110;  // 行0
                2'd1: row <= 4'b1101;  // 行1
                2'd2: row <= 4'b1011;  // 行2
                2'd3: row <= 4'b0111;  // 行3
                default: row <= 4'b1110;
            endcase
        end else begin
            debounce_cnt <= debounce_cnt + 1'b1;
        end

        // 消抖与按键编码（检测到列信号低电平，且稳定20ms）
        if (col != 4'b1111) begin  // 有按键按下
            if (debounce_cnt >= 20'd999999) begin  // 20ms@50MHz（50M×0.02=1e6，取999999）
                key_press <= 1'b1;
                // 根据当前扫描行和列信号，查表获取按键编码
                case (scan_state)
                    2'd0: key_code <= key_map[col];  // 行0
                    2'd1: key_code <= key_map[4+col]; // 行1
                    2'd2: key_code <= key_map[8+col]; // 行2
                    2'd3: key_code <= key_map[12+col];// 行3
                endcase
            end
        end else begin
            key_press <= 1'b0;
        end
    end
end
endmodule