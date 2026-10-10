module tb_expG_scale_rv32imb_16b_ctr;
    localparam [31:0] START_ADDR = 32'h0000ff00;
    localparam [31:0] STOP_ADDR = 32'h0000ff04;
    localparam [31:0] ERRORS_ADDR = 32'h0000ff08;
    localparam [31:0] STATUS_ADDR = 32'h0000ff0c;
    localparam integer OUTPUT_INDEX = 769;
    localparam integer BLOCKS = 1;
    localparam integer PAYLOAD_BYTES = 16;

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
                $display("============================================================");
                $display("[SOFTWARE_AES_SUMMARY] CORE=RV32IMB MODE=CTR PAYLOAD_BYTES=%0d BLOCKS=%0d", PAYLOAD_BYTES, BLOCKS);
                $display("[SOFTWARE_AES_SUMMARY] MEASURE_WINDOW=START_MARKER_TO_STOP_MARKER START_CYCLE=%0d STOP_CYCLE=%0d", start_cycle, start_cycle+raw_cycles);
                $display("[SOFTWARE_AES_SUMMARY] TOTAL_CYCLES=%0d CYCLES_PER_BLOCK=%0f RETIRED=%0d CPI=%0f", raw_cycles, raw_cycles/(BLOCKS*1.0), retired, raw_cycles/(retired*1.0));
                $display("============================================================");
                $display("[EXP_G] CORE=RV32IMB MODE=CTR REPEAT=%0d PAYLOAD_BYTES=%0d BLOCKS=%0d", repeat_id, PAYLOAD_BYTES, BLOCKS);
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
        expected_byte[0] = 8'h87;
        expected_byte[1] = 8'h4d;
        expected_byte[2] = 8'h61;
        expected_byte[3] = 8'h91;
        expected_byte[4] = 8'hb6;
        expected_byte[5] = 8'h20;
        expected_byte[6] = 8'he3;
        expected_byte[7] = 8'h26;
        expected_byte[8] = 8'h1b;
        expected_byte[9] = 8'hef;
        expected_byte[10] = 8'h68;
        expected_byte[11] = 8'h64;
        expected_byte[12] = 8'h99;
        expected_byte[13] = 8'h0d;
        expected_byte[14] = 8'hb6;
        expected_byte[15] = 8'hce;
        $readmemh("expG_16B_CTR.mem", unified_mem);
        #200;
        rst_n = 1;
    end

    initial begin
        #100000000;
        $display("============================================================");
        $display("[SOFTWARE_AES_SUMMARY] CORE=RV32IMB MODE=CTR PAYLOAD_BYTES=%0d BLOCKS=%0d", PAYLOAD_BYTES, BLOCKS);
        $display("[SOFTWARE_AES_SUMMARY] MEASURE_WINDOW=START_MARKER_TO_STOP_MARKER START_CYCLE=%0d STOP_CYCLE=%0d", start_cycle, start_cycle+raw_cycles);
        $display("[SOFTWARE_AES_SUMMARY] TOTAL_CYCLES=%0d CYCLES_PER_BLOCK=%0f RETIRED=%0d CPI=%0f", raw_cycles, raw_cycles/(BLOCKS*1.0), retired, raw_cycles/(retired*1.0));
        $display("============================================================");
        $display("[EXP_G] CORE=RV32IMB MODE=CTR REPEAT=%0d RESULT=TIMEOUT PC=%08x INSN=%08x CYCLE=%0d MEM_ADDR=%08x", repeat_id, INST_ADDR, INST_DATA, cycle_count, MEM_ADDR);
        $finish;
    end
endmodule
