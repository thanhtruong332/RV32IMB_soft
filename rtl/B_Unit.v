module B_Unit (
    input   wire    [31:0]  rs1,
    input   wire    [1:0]   b_op, // 00: CLZ, 01: CTZ, 10: CPOP
    output  reg     [31:0]  b_result
);
    integer i;
    reg [5:0] count;
    reg found;

    always @(*) begin
        count = 0;
        found = 0;
        b_result = 0;

        case (b_op)
            2'b00: begin // CLZ: Count Leading Zeros
                for (i = 31; i >= 0; i = i - 1) begin
                    if (rs1[i] == 1'b1) found = 1;
                    if (!found) count = count + 1;
                end
                b_result = count;
            end

            2'b01: begin // CTZ: Count Trailing Zeros
                for (i = 0; i <= 31; i = i + 1) begin
                    if (rs1[i] == 1'b1) found = 1;
                    if (!found) count = count + 1;
                end
                b_result = count;
            end

            2'b10: begin
                for (i = 0; i <= 31; i = i + 1) begin
                    if (rs1[i] == 1'b1) count = count + 1;
                end
                b_result = count;
            end

            default: b_result = 32'b0;
        endcase
    end
endmodule
