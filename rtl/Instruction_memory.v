module Instruction_memory (
    input   wire    [31:0]  pc,
    output  wire    [31:0]  Instruction
);
    reg [31:0]  mem [0:1023];
    integer i;

   initial begin

        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'h00000013; // NOP

        mem[0] = 32'h06000093; // addi x1, x0, 96

        // RISC-V encodings for CLZ, CTZ and CPOP.
        mem[1] = 32'h60009133;
        mem[2] = 32'h6000A1B3;
        mem[3] = 32'h6000B233;

        mem[4] = 32'h00202023;
        mem[5] = 32'h00302223;
        mem[6] = 32'h00402423;

        mem[7] = 32'h00000013; // NOP
        mem[8] = 32'h00000013; // NOP
    end
    assign  Instruction =   mem[pc[31:2]];
endmodule
