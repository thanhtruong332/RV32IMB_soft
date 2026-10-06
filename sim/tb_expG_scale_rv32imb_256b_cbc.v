module tb_expG_scale_rv32imb_256b_cbc;
    localparam [31:0] START_ADDR = 32'h0000ff00;
    localparam [31:0] STOP_ADDR = 32'h0000ff04;
    localparam [31:0] ERRORS_ADDR = 32'h0000ff08;
    localparam [31:0] STATUS_ADDR = 32'h0000ff0c;
    localparam integer OUTPUT_INDEX = 770;
    localparam integer BLOCKS = 16;
    localparam integer PAYLOAD_BYTES = 256;

    reg clk = 0;
    reg rst_n = 0;
    reg [31:0] MEM_RDATA = 0;
    reg MEM_READY = 1;
    wire [31:0] MEM_ADDR, MEM_WDATA, INST_ADDR, INST_DATA;
    wire MEM_WRITE, MEM_READ, CPU_DATA, CPU_PRIVILEGED;
    wire [3:0] HPROT;
    

    reg [31:0] unified_mem [0:16383];
    reg [7:0] expected_byte [0:PAYLOAD_BYTES-1];
    integer i;
    integer mem_index;
    integer repeat_id = 0;
    integer firmware_errors = -1;
    integer observed_errors = 0;
    integer cycle_count = 0;
    integer start_cycle = 0;
    integer raw_cycles = 0;
    integer retired = 0;
    integer alu_count = 0;
    integer load_count = 0;
    integer store_count = 0;
    integer branch_count = 0;
    integer taken_branch_count = 0;
    integer branch_penalty_cycles = 0;
    integer jump_count = 0;
    integer m_count = 0;
    integer b_count = 0;
    integer total_stalls = 0;
    integer control_stalls = 0;
    integer load_use_stalls = 0;
    integer memory_stalls = 0;
    integer derived_total_stalls = 0;
    integer counter_errors = 0;
    reg profile_active = 0;
    reg profile_complete = 0;

    rv32i_top DUT (
        .clk(clk), .rst_n(rst_n), .MEM_RDATA(MEM_RDATA), .MEM_READY(MEM_READY),
        .CPU_DATA(CPU_DATA), .CPU_PRIVILEGED(CPU_PRIVILEGED), .HPROT(HPROT),
        .MEM_ADDR(MEM_ADDR), .MEM_WDATA(MEM_WDATA), .MEM_WRITE(MEM_WRITE),
        .MEM_READ(MEM_READ), .INST_ADDR(INST_ADDR), .INST_DATA(INST_DATA)
    );

    always #12.5 clk = ~clk;
    assign INST_DATA = (^INST_ADDR === 1'bx) ? 32'h00000013 : unified_mem[(INST_ADDR & 32'h0000ffff) >> 2];

    always @(*) begin
        if (MEM_READ && (^MEM_ADDR !== 1'bx))
            MEM_RDATA = unified_mem[(MEM_ADDR & 32'h0000ffff) >> 2];
        else
            MEM_RDATA = 32'h0;
    end

    reg prof_ifid_valid = 0;
    reg prof_idex_valid = 0;
    reg prof_exmem_valid = 0;
    reg prof_memwb_valid = 0;
    reg prof_idex_count = 0;
    reg prof_exmem_count = 0;
    reg prof_memwb_count = 0;
    reg [31:0] prof_idex_insn = 0;
    reg [31:0] prof_exmem_insn = 0;
    reg [31:0] prof_memwb_insn = 0;
    wire prof_start_event = prof_idex_valid && DUT.ID_EX_Mem_Write && DUT.ALU_result == START_ADDR;
    wire prof_stop_event = prof_idex_valid && DUT.ID_EX_Mem_Write && DUT.ALU_result == STOP_ADDR;

    // Shadow the pipeline so instruction metrics are sampled at MEM/WB (commit).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prof_ifid_valid <= 0;
            prof_idex_valid <= 0;
            prof_exmem_valid <= 0;
            prof_memwb_valid <= 0;
            prof_idex_count <= 0;
            prof_exmem_count <= 0;
            prof_memwb_count <= 0;
            prof_idex_insn <= 0;
            prof_exmem_insn <= 0;
            prof_memwb_insn <= 0;
        end else begin
            if (DUT.Flush)
                prof_ifid_valid <= 0;
            else if (!DUT.Stall)
                prof_ifid_valid <= 1;

            if (DUT.Stall || DUT.ID_Flush || DUT.Flush) begin
                prof_idex_valid <= 0;
                prof_idex_count <= 0;
                prof_idex_insn <= 0;
            end else begin
                prof_idex_valid <= prof_ifid_valid;
                prof_idex_count <= (profile_active || prof_start_event) && !prof_stop_event;
                prof_idex_insn <= DUT.IF_ID_Instruction;
            end

            if (!DUT.bus_stall) begin
                prof_exmem_valid <= prof_idex_valid;
                prof_exmem_count <= prof_idex_count && !prof_start_event && !prof_stop_event;
                prof_exmem_insn <= prof_idex_insn;
                prof_memwb_valid <= prof_exmem_valid;
                prof_memwb_count <= prof_exmem_count;
                prof_memwb_insn <= prof_exmem_insn;
            end
        end
    end

    task count_instruction;
        input [31:0] instruction;
        reg [6:0] opcode;
        reg [6:0] funct7;
        begin
            opcode = instruction[6:0];
            funct7 = instruction[31:25];
            retired <= retired + 1;
            case (opcode)
                7'b0000011: load_count <= load_count + 1;
                7'b0100011: store_count <= store_count + 1;
                7'b1100011: begin
                    branch_count <= branch_count + 1;
                    // RISSP resolves the branch in its single-instruction datapath.
                    // A non-sequential next_pc is therefore a directly observed taken branch.
                    if (1'b0)
                        taken_branch_count <= taken_branch_count + 1;
                end
                7'b1101111, 7'b1100111: jump_count <= jump_count + 1;
                default: alu_count <= alu_count + 1;
            endcase
            if (opcode == 7'b0110011 && funct7 == 7'b0000001)
                m_count <= m_count + 1;
            if ((opcode == 7'b0110011 || opcode == 7'b0010011) && funct7 == 7'b0110000)
                b_count <= b_count + 1;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            profile_active <= 0;
            profile_complete <= 0;
            start_cycle <= 0;
            raw_cycles <= 0;
            retired <= 0;
            alu_count <= 0;
            load_count <= 0;
            store_count <= 0;
            branch_count <= 0;
            taken_branch_count <= 0;
            branch_penalty_cycles <= 0;
            jump_count <= 0;
            m_count <= 0;
            b_count <= 0;
            total_stalls <= 0;
            control_stalls <= 0;
            load_use_stalls <= 0;
            memory_stalls <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (prof_idex_valid && DUT.ID_EX_Mem_Write && DUT.ALU_result == START_ADDR) begin
                profile_active <= 1;
                profile_complete <= 0;
                start_cycle <= cycle_count;
                retired <= 0;
                alu_count <= 0;
                load_count <= 0;
                store_count <= 0;
                branch_count <= 0;
                taken_branch_count <= 0;
                branch_penalty_cycles <= 0;
                jump_count <= 0;
                m_count <= 0;
                b_count <= 0;
                total_stalls <= 0;
                control_stalls <= 0;
                load_use_stalls <= 0;
                memory_stalls <= 0;
            end else begin
                if (prof_idex_valid && DUT.ID_EX_Mem_Write && DUT.ALU_result == STOP_ADDR) begin
                    profile_active <= 0;
                    profile_complete <= 1;
                    raw_cycles <= cycle_count - start_cycle;
                end
                if (prof_memwb_valid && prof_memwb_count)
                    count_instruction(prof_memwb_insn);
            end
            if (profile_active && !prof_stop_event) begin
                // A taken branch/jump flushes the two younger IF/ID and ID/EX slots.
                if (DUT.Flush) control_stalls <= control_stalls + 2;
                // Count conditional branches from the actual EX-stage resolution signal.
                if (DUT.ID_EX_Branch && DUT.Branch_taken) begin
                    taken_branch_count <= taken_branch_count + 1;
                    branch_penalty_cycles <= branch_penalty_cycles + 2;
                end
                if (DUT.hazard_stall) load_use_stalls <= load_use_stalls + 1;
                if (DUT.bus_stall) memory_stalls <= memory_stalls + 1;
            end
        end
    end




    always @(posedge clk) begin
        if (rst_n && MEM_WRITE && MEM_READY && (^MEM_ADDR !== 1'bx)) begin
            mem_index = (MEM_ADDR & 32'h0000ffff) >> 2;
            unified_mem[mem_index] <= MEM_WDATA;
            if (MEM_ADDR == ERRORS_ADDR)
                firmware_errors = MEM_WDATA;
            if (MEM_ADDR == STATUS_ADDR) begin
                observed_errors = 0;
                counter_errors = 0;
                derived_total_stalls = raw_cycles - retired - 1;
                for (i = 0; i < PAYLOAD_BYTES; i = i + 1)
                    if (unified_mem[OUTPUT_INDEX+i][7:0] !== expected_byte[i])
                        observed_errors = observed_errors + 1;
                if (retired != alu_count + load_count + store_count + branch_count + jump_count)
                    counter_errors = counter_errors + 1;
                if (taken_branch_count > branch_count)
                    counter_errors = counter_errors + 1;
                if (derived_total_stalls < 0)
                    counter_errors = counter_errors + 1;
                if (derived_total_stalls != control_stalls + load_use_stalls + memory_stalls)
                    counter_errors = counter_errors + 1;
                $display("[EXP_G] CORE=RV32IMB MODE=CBC REPEAT=%0d PAYLOAD_BYTES=%0d BLOCKS=%0d", repeat_id, PAYLOAD_BYTES, BLOCKS);
                $display("[EXP_G] START=%0d STOP=%0d RAW_CYCLES=%0d CYCLES_PER_BLOCK=%0f", start_cycle, start_cycle+raw_cycles, raw_cycles, raw_cycles/(BLOCKS*1.0));
                $display("[EXP_G] RETIRED=%0d CPI=%0f ALU=%0d LOAD=%0d STORE=%0d BRANCH=%0d JUMP=%0d M=%0d B=%0d", retired, raw_cycles/(retired*1.0), alu_count, load_count, store_count, branch_count, jump_count, m_count, b_count);
                $display("[EXP_G] TAKEN_BRANCH=%0d BRANCH_PENALTY_CYCLES=%0d", taken_branch_count, branch_penalty_cycles);
                $display("[EXP_G] TOTAL_STALLS=%0d CONTROL_STALLS=%0d LOAD_USE_STALLS=%0d MEMORY_STALLS=%0d OTHER_STALLS=%0d", derived_total_stalls, control_stalls, load_use_stalls, memory_stalls, derived_total_stalls-control_stalls-load_use_stalls-memory_stalls);
                $display("[EXP_G] COUNTER_ERRORS=%0d COUNTER_CHECK=%s", counter_errors, counter_errors==0 ? "PASS" : "FAIL");
                $display("[EXP_G] FW_ERRORS=%0d TB_ERRORS=%0d STATUS=%08x RESULT=%s", firmware_errors, observed_errors, MEM_WDATA, (MEM_WDATA==32'h50415353 && firmware_errors==0 && observed_errors==0 && counter_errors==0 && profile_complete) ? "PASS" : "FAIL");
                $display("[EXP_G] BLOCKS_CHECKED=%0d BYTES_CHECKED=%0d", BLOCKS, PAYLOAD_BYTES);
                for (i = 0; i < BLOCKS; i = i + 1) begin
                    $write("[EXP_G_BLOCK] BLOCK=%0d OBSERVED=", i+1);
                    $write("%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x ",
                        unified_mem[OUTPUT_INDEX+i*16+0][7:0], unified_mem[OUTPUT_INDEX+i*16+1][7:0],
                        unified_mem[OUTPUT_INDEX+i*16+2][7:0], unified_mem[OUTPUT_INDEX+i*16+3][7:0],
                        unified_mem[OUTPUT_INDEX+i*16+4][7:0], unified_mem[OUTPUT_INDEX+i*16+5][7:0],
                        unified_mem[OUTPUT_INDEX+i*16+6][7:0], unified_mem[OUTPUT_INDEX+i*16+7][7:0],
                        unified_mem[OUTPUT_INDEX+i*16+8][7:0], unified_mem[OUTPUT_INDEX+i*16+9][7:0],
                        unified_mem[OUTPUT_INDEX+i*16+10][7:0], unified_mem[OUTPUT_INDEX+i*16+11][7:0],
                        unified_mem[OUTPUT_INDEX+i*16+12][7:0], unified_mem[OUTPUT_INDEX+i*16+13][7:0],
                        unified_mem[OUTPUT_INDEX+i*16+14][7:0], unified_mem[OUTPUT_INDEX+i*16+15][7:0]);
                    $write("EXPECTED=");
                    $write("%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x\n",
                        expected_byte[i*16+0], expected_byte[i*16+1], expected_byte[i*16+2], expected_byte[i*16+3],
                        expected_byte[i*16+4], expected_byte[i*16+5], expected_byte[i*16+6], expected_byte[i*16+7],
                        expected_byte[i*16+8], expected_byte[i*16+9], expected_byte[i*16+10], expected_byte[i*16+11],
                        expected_byte[i*16+12], expected_byte[i*16+13], expected_byte[i*16+14], expected_byte[i*16+15]);
                end
                #100;
                $finish;
            end
        end
    end

`ifdef EXP_G_DEBUG
    always @(posedge clk) begin
        if (rst_n && (cycle_count < 60 || (cycle_count % 100000) == 0))
            $display("[EXP_G_DEBUG] CYCLE=%0d PC=%08x INSN=%08x MEMR=%b MEMW=%b ADDR=%08x WDATA=%08x PROFILE=%b", cycle_count, INST_ADDR, INST_DATA, MEM_READ, MEM_WRITE, MEM_ADDR, MEM_WDATA, profile_active);
    end
`endif

    initial begin
        if (!$value$plusargs("REPEAT=%d", repeat_id)) repeat_id = 1;
        for (i = 0; i < 16384; i = i + 1) unified_mem[i] = 0;
        expected_byte[0] = 8'h76;
        expected_byte[1] = 8'h49;
        expected_byte[2] = 8'hab;
        expected_byte[3] = 8'hac;
        expected_byte[4] = 8'h81;
        expected_byte[5] = 8'h19;
        expected_byte[6] = 8'hb2;
        expected_byte[7] = 8'h46;
        expected_byte[8] = 8'hce;
        expected_byte[9] = 8'he9;
        expected_byte[10] = 8'h8e;
        expected_byte[11] = 8'h9b;
        expected_byte[12] = 8'h12;
        expected_byte[13] = 8'he9;
        expected_byte[14] = 8'h19;
        expected_byte[15] = 8'h7d;
        expected_byte[16] = 8'h50;
        expected_byte[17] = 8'h86;
        expected_byte[18] = 8'hcb;
        expected_byte[19] = 8'h9b;
        expected_byte[20] = 8'h50;
        expected_byte[21] = 8'h72;
        expected_byte[22] = 8'h19;
        expected_byte[23] = 8'hee;
        expected_byte[24] = 8'h95;
        expected_byte[25] = 8'hdb;
        expected_byte[26] = 8'h11;
        expected_byte[27] = 8'h3a;
        expected_byte[28] = 8'h91;
        expected_byte[29] = 8'h76;
        expected_byte[30] = 8'h78;
        expected_byte[31] = 8'hb2;
        expected_byte[32] = 8'h73;
        expected_byte[33] = 8'hbe;
        expected_byte[34] = 8'hd6;
        expected_byte[35] = 8'hb8;
        expected_byte[36] = 8'he3;
        expected_byte[37] = 8'hc1;
        expected_byte[38] = 8'h74;
        expected_byte[39] = 8'h3b;
        expected_byte[40] = 8'h71;
        expected_byte[41] = 8'h16;
        expected_byte[42] = 8'he6;
        expected_byte[43] = 8'h9e;
        expected_byte[44] = 8'h22;
        expected_byte[45] = 8'h22;
        expected_byte[46] = 8'h95;
        expected_byte[47] = 8'h16;
        expected_byte[48] = 8'h3f;
        expected_byte[49] = 8'hf1;
        expected_byte[50] = 8'hca;
        expected_byte[51] = 8'ha1;
        expected_byte[52] = 8'h68;
        expected_byte[53] = 8'h1f;
        expected_byte[54] = 8'hac;
        expected_byte[55] = 8'h09;
        expected_byte[56] = 8'h12;
        expected_byte[57] = 8'h0e;
        expected_byte[58] = 8'hca;
        expected_byte[59] = 8'h30;
        expected_byte[60] = 8'h75;
        expected_byte[61] = 8'h86;
        expected_byte[62] = 8'he1;
        expected_byte[63] = 8'ha7;
        expected_byte[64] = 8'hec;
        expected_byte[65] = 8'h20;
        expected_byte[66] = 8'h77;
        expected_byte[67] = 8'h6f;
        expected_byte[68] = 8'haf;
        expected_byte[69] = 8'h25;
        expected_byte[70] = 8'ha4;
        expected_byte[71] = 8'hb3;
        expected_byte[72] = 8'h54;
        expected_byte[73] = 8'h84;
        expected_byte[74] = 8'h6a;
        expected_byte[75] = 8'h50;
        expected_byte[76] = 8'hff;
        expected_byte[77] = 8'h7a;
        expected_byte[78] = 8'hb1;
        expected_byte[79] = 8'h6b;
        expected_byte[80] = 8'h74;
        expected_byte[81] = 8'h45;
        expected_byte[82] = 8'hd2;
        expected_byte[83] = 8'h01;
        expected_byte[84] = 8'he0;
        expected_byte[85] = 8'h8d;
        expected_byte[86] = 8'h61;
        expected_byte[87] = 8'hac;
        expected_byte[88] = 8'h1f;
        expected_byte[89] = 8'h38;
        expected_byte[90] = 8'hef;
        expected_byte[91] = 8'h8e;
        expected_byte[92] = 8'h82;
        expected_byte[93] = 8'h16;
        expected_byte[94] = 8'heb;
        expected_byte[95] = 8'hfb;
        expected_byte[96] = 8'ha7;
        expected_byte[97] = 8'h90;
        expected_byte[98] = 8'h32;
        expected_byte[99] = 8'hc1;
        expected_byte[100] = 8'h81;
        expected_byte[101] = 8'h73;
        expected_byte[102] = 8'h88;
        expected_byte[103] = 8'he9;
        expected_byte[104] = 8'h0c;
        expected_byte[105] = 8'ha4;
        expected_byte[106] = 8'h3c;
        expected_byte[107] = 8'h71;
        expected_byte[108] = 8'he2;
        expected_byte[109] = 8'h49;
        expected_byte[110] = 8'h41;
        expected_byte[111] = 8'ha5;
        expected_byte[112] = 8'h05;
        expected_byte[113] = 8'hd6;
        expected_byte[114] = 8'hb4;
        expected_byte[115] = 8'ha1;
        expected_byte[116] = 8'h2f;
        expected_byte[117] = 8'h95;
        expected_byte[118] = 8'h5a;
        expected_byte[119] = 8'h05;
        expected_byte[120] = 8'h45;
        expected_byte[121] = 8'hd6;
        expected_byte[122] = 8'hfa;
        expected_byte[123] = 8'h84;
        expected_byte[124] = 8'hf4;
        expected_byte[125] = 8'hc9;
        expected_byte[126] = 8'h70;
        expected_byte[127] = 8'h60;
        expected_byte[128] = 8'h87;
        expected_byte[129] = 8'h83;
        expected_byte[130] = 8'he9;
        expected_byte[131] = 8'h68;
        expected_byte[132] = 8'hb1;
        expected_byte[133] = 8'he3;
        expected_byte[134] = 8'hdc;
        expected_byte[135] = 8'hd9;
        expected_byte[136] = 8'h71;
        expected_byte[137] = 8'h37;
        expected_byte[138] = 8'h8c;
        expected_byte[139] = 8'h62;
        expected_byte[140] = 8'h77;
        expected_byte[141] = 8'h36;
        expected_byte[142] = 8'hc3;
        expected_byte[143] = 8'h12;
        expected_byte[144] = 8'hde;
        expected_byte[145] = 8'h1e;
        expected_byte[146] = 8'ha4;
        expected_byte[147] = 8'h46;
        expected_byte[148] = 8'h45;
        expected_byte[149] = 8'h64;
        expected_byte[150] = 8'h9d;
        expected_byte[151] = 8'hcb;
        expected_byte[152] = 8'hed;
        expected_byte[153] = 8'h61;
        expected_byte[154] = 8'h8c;
        expected_byte[155] = 8'h61;
        expected_byte[156] = 8'hd8;
        expected_byte[157] = 8'h09;
        expected_byte[158] = 8'h4b;
        expected_byte[159] = 8'h8e;
        expected_byte[160] = 8'hae;
        expected_byte[161] = 8'ha2;
        expected_byte[162] = 8'h62;
        expected_byte[163] = 8'h62;
        expected_byte[164] = 8'hf9;
        expected_byte[165] = 8'ha7;
        expected_byte[166] = 8'h2f;
        expected_byte[167] = 8'hc9;
        expected_byte[168] = 8'h77;
        expected_byte[169] = 8'h34;
        expected_byte[170] = 8'h3d;
        expected_byte[171] = 8'hb5;
        expected_byte[172] = 8'hc0;
        expected_byte[173] = 8'he1;
        expected_byte[174] = 8'h77;
        expected_byte[175] = 8'h74;
        expected_byte[176] = 8'hde;
        expected_byte[177] = 8'he3;
        expected_byte[178] = 8'h91;
        expected_byte[179] = 8'h5f;
        expected_byte[180] = 8'hae;
        expected_byte[181] = 8'h73;
        expected_byte[182] = 8'h7c;
        expected_byte[183] = 8'hcc;
        expected_byte[184] = 8'hc0;
        expected_byte[185] = 8'hc7;
        expected_byte[186] = 8'h32;
        expected_byte[187] = 8'he3;
        expected_byte[188] = 8'h33;
        expected_byte[189] = 8'h58;
        expected_byte[190] = 8'h84;
        expected_byte[191] = 8'h50;
        expected_byte[192] = 8'h74;
        expected_byte[193] = 8'h50;
        expected_byte[194] = 8'h36;
        expected_byte[195] = 8'h2c;
        expected_byte[196] = 8'h4f;
        expected_byte[197] = 8'hb1;
        expected_byte[198] = 8'h0f;
        expected_byte[199] = 8'hc0;
        expected_byte[200] = 8'hc1;
        expected_byte[201] = 8'h2a;
        expected_byte[202] = 8'h3d;
        expected_byte[203] = 8'h71;
        expected_byte[204] = 8'hdf;
        expected_byte[205] = 8'hb4;
        expected_byte[206] = 8'hc8;
        expected_byte[207] = 8'h85;
        expected_byte[208] = 8'h8a;
        expected_byte[209] = 8'hcd;
        expected_byte[210] = 8'hf2;
        expected_byte[211] = 8'h4f;
        expected_byte[212] = 8'h93;
        expected_byte[213] = 8'hb0;
        expected_byte[214] = 8'ha7;
        expected_byte[215] = 8'he8;
        expected_byte[216] = 8'he4;
        expected_byte[217] = 8'h3a;
        expected_byte[218] = 8'h5f;
        expected_byte[219] = 8'ha6;
        expected_byte[220] = 8'he5;
        expected_byte[221] = 8'h7c;
        expected_byte[222] = 8'h4b;
        expected_byte[223] = 8'h94;
        expected_byte[224] = 8'hcf;
        expected_byte[225] = 8'hf1;
        expected_byte[226] = 8'h25;
        expected_byte[227] = 8'hb0;
        expected_byte[228] = 8'h4e;
        expected_byte[229] = 8'hfd;
        expected_byte[230] = 8'hd5;
        expected_byte[231] = 8'h4d;
        expected_byte[232] = 8'hdf;
        expected_byte[233] = 8'hde;
        expected_byte[234] = 8'hd7;
        expected_byte[235] = 8'h06;
        expected_byte[236] = 8'h7d;
        expected_byte[237] = 8'h32;
        expected_byte[238] = 8'hc7;
        expected_byte[239] = 8'h8b;
        expected_byte[240] = 8'h28;
        expected_byte[241] = 8'h23;
        expected_byte[242] = 8'h88;
        expected_byte[243] = 8'ha4;
        expected_byte[244] = 8'h52;
        expected_byte[245] = 8'h37;
        expected_byte[246] = 8'h23;
        expected_byte[247] = 8'hfb;
        expected_byte[248] = 8'hd7;
        expected_byte[249] = 8'h51;
        expected_byte[250] = 8'hec;
        expected_byte[251] = 8'h26;
        expected_byte[252] = 8'h8d;
        expected_byte[253] = 8'hd2;
        expected_byte[254] = 8'h88;
        expected_byte[255] = 8'h43;
        $readmemh("expG_256B_CBC.mem", unified_mem);
        #200;
        rst_n = 1;
    end

    initial begin
        #100000000;
        $display("[EXP_G] CORE=RV32IMB MODE=CBC REPEAT=%0d RESULT=TIMEOUT PC=%08x INSN=%08x CYCLE=%0d MEM_ADDR=%08x", repeat_id, INST_ADDR, INST_DATA, cycle_count, MEM_ADDR);
        $finish;
    end
endmodule
