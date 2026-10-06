module M_Unit(
    input   wire    [31:0]  rs1,
    input   wire    [31:0]  rs2,
    input   wire    [2:0]   funct3,
    output  reg     [31:0]  m_result
);
    wire signed [63:0] mul_signed   = $signed(rs1) * $signed(rs2);
    wire signed [63:0] mul_su       = $signed(rs1) * $signed({1'b0, rs2});
    wire        [63:0] mul_unsigned = rs1 * rs2;

    always @(*) begin
        case(funct3)
            3'b000: m_result = mul_signed[31:0];         // MUL
            3'b001: m_result = mul_signed[63:32];        // MULH
            3'b010: m_result = mul_su[63:32];            // MULHSU
            3'b011: m_result = mul_unsigned[63:32];      // MULHU
            // Lưu ý: Phép chia đơn chu kỳ (/) chỉ dùng để Simulation. 
            // Khi tổng hợp (Synthesis) thực tế sẽ gây trễ (delay) cực lớn.
            3'b100: m_result = (rs2 == 0) ? 32'hFFFF_FFFF : ($signed(rs1) / $signed(rs2)); // DIV
            3'b101: m_result = (rs2 == 0) ? 32'hFFFF_FFFF : (rs1 / rs2);                   // DIVU
            3'b110: m_result = (rs2 == 0) ? rs1 : ($signed(rs1) % $signed(rs2));           // REM
            3'b111: m_result = (rs2 == 0) ? rs1 : (rs1 % rs2);                             // REMU
            default: m_result = 32'b0;
        endcase
    end
endmodule
