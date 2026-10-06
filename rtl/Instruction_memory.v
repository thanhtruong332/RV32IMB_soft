module Instruction_memory(
    input   wire    [31:0]  pc,
    output  wire    [31:0]  Instruction
);
    reg [31:0]  mem [0:1023];
    integer i;

   initial begin
        
        for(i = 0; i < 1024; i = i + 1)
            mem[i] = 32'h00000013; // NOP

        // CHƯƠNG TRÌNH TEST B-EXTENSION (Zbb)
        
        // 1. Nạp số 96 vào thanh ghi x1
        mem[0] = 32'h06000093; // addi x1, x0, 96
        
        // 2. Chạy qua B-Unit
        // RISC-V encodings for CLZ, CTZ and CPOP.
        mem[1] = 32'h60009133; // clz  x2, x1   (Đếm bit 0 ở đầu -> mong đợi: 25)
        mem[2] = 32'h6000A1B3; // ctz  x3, x1   (Đếm bit 0 ở đuôi -> mong đợi: 5)
        mem[3] = 32'h6000B233; // cpop x4, x1   (Đếm tổng bit 1 -> mong đợi: 2)

        // 3. Ghi kết quả ra RAM (Để in ra Console)
        mem[4] = 32'h00202023; // sw x2, 0(x0)  -> Ghi số 25 vào địa chỉ 0x0
        mem[5] = 32'h00302223; // sw x3, 4(x0)  -> Ghi số 5 vào địa chỉ 0x4
        mem[6] = 32'h00402423; // sw x4, 8(x0)  -> Ghi số 2 vào địa chỉ 0x8
        
        mem[7] = 32'h00000013; // NOP
        mem[8] = 32'h00000013; // NOP
    end
    assign  Instruction =   mem[pc[31:2]]; 
endmodule
