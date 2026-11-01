`timescale 1ns/1ps
`default_nettype none

module tb_hazard_control;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic dmem_read, dmem_write;
    logic [3:0] dmem_wstrb;
    logic retire_valid, retire_rd_we, retire_store_we;
    logic [31:0] retire_pc, retire_insn, retire_rd_data;
    logic [4:0] retire_rd;
    logic [31:0] retire_store_addr, retire_store_wdata;
    logic [3:0] retire_store_wstrb;
    logic stop;
    logic [1:0] stop_cause;
    logic [31:0] stop_pc;

    logic [31:0] imem [0:255];
    logic [7:0] dmem [0:4095];
    logic [31:0] exp_pc [0:255];
    logic exp_we [0:255], exp_store [0:255];
    logic [4:0] exp_rd [0:255];
    logic [31:0] exp_value [0:255], exp_store_addr [0:255], exp_store_data [0:255];
    logic [3:0] exp_store_strb [0:255];
    integer program_count = 0;
    integer expected_count = 0;
    integer retire_count = 0;
    integer stall_count = 0;
    integer store_count = 0;
    integer failure_count = 0;
    integer byte_base;
    integer i;

    always #5 clk = ~clk;

    always_comb begin
        imem_rdata = imem[imem_addr[9:2]];
        byte_base = dmem_addr[11:2] * 4;
        dmem_rdata = {dmem[byte_base+3], dmem[byte_base+2],
                      dmem[byte_base+1], dmem[byte_base]};
    end

    always @(posedge clk) begin
        if (rst_n && dmem_write) begin
            store_count = store_count + 1;
            for (integer lane=0; lane<4; lane=lane+1)
                if (dmem_wstrb[lane]) dmem[byte_base+lane] <= dmem_wdata[8*lane +: 8];
        end
        if (rst_n && dut.load_use_stall) stall_count = stall_count + 1;
        if (retire_valid) begin
            if (retire_count >= expected_count) begin
                $display("FAIL: unexpected retirement pc=%08x", retire_pc);
                failure_count = failure_count + 1;
            end else begin
                if (retire_pc !== exp_pc[retire_count]) begin
                    $display("FAIL: retirement[%0d] expected pc=%08x got=%08x",
                             retire_count, exp_pc[retire_count], retire_pc);
                    failure_count = failure_count + 1;
                end
                if (retire_rd_we !== exp_we[retire_count]) begin
                    $display("FAIL: pc=%08x rd_we expected=%b got=%b",
                             retire_pc, exp_we[retire_count], retire_rd_we);
                    failure_count = failure_count + 1;
                end
                if (exp_we[retire_count] &&
                    (retire_rd !== exp_rd[retire_count] || retire_rd_data !== exp_value[retire_count])) begin
                    $display("FAIL: pc=%08x expected x%0d=%08x got x%0d=%08x",
                             retire_pc, exp_rd[retire_count], exp_value[retire_count],
                             retire_rd, retire_rd_data);
                    failure_count = failure_count + 1;
                end
                if (retire_store_we !== exp_store[retire_count]) begin
                    $display("FAIL: pc=%08x store_we expected=%b got=%b",
                             retire_pc, exp_store[retire_count], retire_store_we);
                    failure_count = failure_count + 1;
                end
                if (exp_store[retire_count] &&
                    (retire_store_addr !== exp_store_addr[retire_count] ||
                     retire_store_wstrb !== exp_store_strb[retire_count] ||
                     retire_store_wdata !== exp_store_data[retire_count])) begin
                    $display("FAIL: pc=%08x store fields mismatch", retire_pc);
                    failure_count = failure_count + 1;
                end
            end
            retire_count = retire_count + 1;
        end
    end

    rv32i_core dut (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_read(dmem_read), .dmem_write(dmem_write),
        .dmem_wstrb(dmem_wstrb), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .retire_valid(retire_valid), .retire_pc(retire_pc), .retire_insn(retire_insn),
        .retire_rd_we(retire_rd_we), .retire_rd(retire_rd), .retire_rd_data(retire_rd_data),
        .retire_store_we(retire_store_we), .retire_store_addr(retire_store_addr),
        .retire_store_wstrb(retire_store_wstrb), .retire_store_wdata(retire_store_wdata),
        .stop(stop), .stop_cause(stop_cause), .stop_pc(stop_pc)
    );

    function automatic [31:0] enc_i(input integer imm, input integer rs1,
                                    input integer funct3, input integer rd,
                                    input integer opcode);
        enc_i = {imm[11:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    endfunction

    function automatic [31:0] enc_r(input integer funct7, input integer rs2,
                                    input integer rs1, input integer funct3,
                                    input integer rd, input integer opcode);
        enc_r = {funct7[6:0], rs2[4:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    endfunction

    function automatic [31:0] enc_s(input integer imm, input integer rs2,
                                    input integer rs1, input integer funct3,
                                    input integer opcode);
        enc_s = {imm[11:5], rs2[4:0], rs1[4:0], funct3[2:0], imm[4:0], opcode[6:0]};
    endfunction

    function automatic [31:0] enc_b(input integer imm, input integer rs2,
                                    input integer rs1, input integer funct3);
        enc_b = {imm[12], imm[10:5], rs2[4:0], rs1[4:0], funct3[2:0],
                 imm[4:1], imm[11], 7'b1100011};
    endfunction

    function automatic [31:0] enc_j(input integer imm, input integer rd);
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd[4:0], 7'b1101111};
    endfunction

    task automatic emit(input logic [31:0] insn, input logic retires,
                        input logic writes_rd, input logic [4:0] rd,
                        input logic [31:0] value, input logic stores,
                        input logic [31:0] store_addr, input logic [3:0] store_strb,
                        input logic [31:0] store_data);
        begin
            imem[program_count] = insn;
            if (retires) begin
                exp_pc[expected_count] = program_count * 4;
                exp_we[expected_count] = writes_rd;
                exp_rd[expected_count] = rd;
                exp_value[expected_count] = value;
                exp_store[expected_count] = stores;
                exp_store_addr[expected_count] = store_addr;
                exp_store_strb[expected_count] = store_strb;
                exp_store_data[expected_count] = store_data;
                expected_count = expected_count + 1;
            end
            program_count = program_count + 1;
        end
    endtask

    task automatic emit_addi(input integer rd, input integer rs1,
                             input integer imm, input logic [31:0] value,
                             input logic retires);
        emit(enc_i(imm, rs1, 0, rd, 7'b0010011), retires, 1'b1, rd[4:0],
             value, 1'b0, 32'b0, 4'b0, 32'b0);
    endtask

    task automatic branch_case(input integer funct3, input integer rs1,
                               input integer rs2, input logic taken,
                               input logic wrong_store);
        begin
            emit(enc_b(8, rs2, rs1, funct3), 1'b1, 1'b0, 5'd0,
                 32'b0, 1'b0, 32'b0, 4'b0, 32'b0);
            if (wrong_store)
                emit(enc_s(0,3,6,2,7'b0100011), !taken, 1'b0, 5'd0,
                     32'b0, !taken, 32'd64, 4'b1111, 32'd13);
            else
                emit_addi(30, 0, 99, 32'd99, !taken);
            emit_addi(31, 0, 1, 32'd1, 1'b1);
        end
    endtask

    initial begin
        for (i=0; i<256; i=i+1) begin
            imem[i] = 32'h0000_0013;
            exp_pc[i] = 32'b0;
            exp_we[i] = 1'b0;
            exp_rd[i] = 5'b0;
            exp_value[i] = 32'b0;
            exp_store[i] = 1'b0;
            exp_store_addr[i] = 32'b0;
            exp_store_strb[i] = 4'b0;
            exp_store_data[i] = 32'b0;
        end
        for (i=0; i<4096; i=i+1) dmem[i] = 8'b0;

        // Back-to-back ALU dependencies exercise EX/MEM, MEM/WB and priority.
        emit_addi(1,0,5,32'd5,1);
        emit_addi(2,1,3,32'd8,1);
        emit(enc_r(0,1,2,0,3,7'b0110011),1,1,3,32'd13,0,0,0,0);
        emit_addi(4,3,1,32'd14,1);
        emit_addi(13,0,1,32'd1,1);
        emit_addi(13,13,1,32'd2,1);
        emit(enc_r(0,13,13,0,14,7'b0110011),1,1,14,32'd4,0,0,0,0);

        // Store/base forwarding, load-use to ALU, and unused rs2 suppression.
        emit_addi(6,0,64,32'd64,1);
        emit(enc_s(0,3,6,2,7'b0100011),1,0,0,0,1,64,4'b1111,32'd13);
        emit(enc_i(0,6,2,7,7'b0000011),1,1,7,32'd13,0,0,0,0);
        emit_addi(8,7,2,32'd15,1);
        emit(enc_i(0,6,2,10,7'b0000011),1,1,10,32'd13,0,0,0,0);
        emit_addi(11,0,10,32'd10,1); // immediate[4:0] matches load rd, but rs2 is unused

        // Load-use to store data, then a load-use branch dependency.
        emit(enc_i(0,6,2,15,7'b0000011),1,1,15,32'd13,0,0,0,0);
        emit(enc_s(4,15,6,2,7'b0100011),1,0,0,0,1,68,4'b1111,32'd13);
        emit(enc_i(0,6,2,16,7'b0000011),1,1,16,32'd13,0,0,0,0);
        emit(enc_b(8,7,16,3'b000),1,0,0,0,0,0,0,0); // taken BEQ; load-use stall
        emit_addi(30,0,99,32'd99,0);
        emit_addi(31,0,1,32'd1,1);

        // Each conditional branch is exercised taken and untaken. A taken
        // BEQ has a wrong-path store to prove that flush suppresses memory IO.
        branch_case(3'b000,1,1,1,1); // BEQ taken
        branch_case(3'b000,1,2,0,0); // BEQ untaken
        branch_case(3'b001,1,2,1,0); // BNE taken
        branch_case(3'b001,1,1,0,0); // BNE untaken
        branch_case(3'b100,1,2,1,0); // BLT taken
        branch_case(3'b100,2,1,0,0); // BLT untaken
        branch_case(3'b101,2,1,1,0); // BGE taken
        branch_case(3'b101,1,2,0,0); // BGE untaken
        branch_case(3'b110,1,2,1,0); // BLTU taken
        branch_case(3'b110,2,1,0,0); // BLTU untaken
        branch_case(3'b111,2,1,1,0); // BGEU taken
        branch_case(3'b111,1,2,0,0); // BGEU untaken

        // JAL link and flush, then forwarded JALR base and link.
        emit(enc_j(8,24),1,1,24,(program_count*4)+4,0,0,0,0);
        emit_addi(30,0,99,32'd99,0);
        emit_addi(31,0,2,32'd2,1);
        emit_addi(22,0,(program_count+3)*4,(program_count+3)*4,1);
        emit(enc_i(0,22,0,23,7'b1100111),1,1,23,(program_count*4)+4,0,0,0,0);
        emit_addi(30,0,99,32'd99,0);
        emit_addi(31,0,3,32'd3,1);

        // A load immediately feeding JALR incurs one bubble; base data is
        // initialized after target PC is known.
        emit(enc_i(128,0,2,18,7'b0000011),1,1,18,(program_count+3)*4,0,0,0,0);
        emit(enc_i(0,18,0,19,7'b1100111),1,1,19,(program_count*4)+4,0,0,0,0);
        emit_addi(30,0,99,32'd99,0);
        emit_addi(31,0,4,32'd4,1);
        dmem[128] = ((program_count-1) * 4) & 8'hff;
        dmem[129] = (((program_count-1) * 4) >> 8) & 8'hff;
        dmem[130] = (((program_count-1) * 4) >> 16) & 8'hff;
        dmem[131] = (((program_count-1) * 4) >> 24) & 8'hff;

        // Misaligned taken jump is the terminal fault; younger work must flush.
        imem[program_count] = enc_j(2,0);
        imem[program_count+1] = enc_s(0,3,6,2,7'b0100011);

        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        wait (stop === 1'b1);
        repeat (5) @(posedge clk);
        #1;
        if (stop_cause !== 2'd3 || stop_pc !== program_count*4) begin
            $display("FAIL: expected PC-alignment stop at %08x; got cause=%0d pc=%08x",
                     program_count*4, stop_cause, stop_pc);
            failure_count = failure_count + 1;
        end
        if (retire_count != expected_count) begin
            $display("FAIL: expected %0d retirements, observed %0d", expected_count, retire_count);
            failure_count = failure_count + 1;
        end
        if (stall_count != 4) begin
            $display("FAIL: expected 4 load-use stalls, observed %0d", stall_count);
            failure_count = failure_count + 1;
        end
        if (store_count != 2) begin
            $display("FAIL: expected 2 stores, observed %0d", store_count);
            failure_count = failure_count + 1;
        end
        if (dmem[64] !== 8'd13 || dmem[68] !== 8'd13) begin
            $display("FAIL: expected committed store values at addresses 64 and 68");
            failure_count = failure_count + 1;
        end
        if (failure_count != 0) begin
            $display("FAIL: hazard/control test; %0d failure(s)", failure_count);
            $fatal(1);
        end else begin
            $display("PASS: hazard/control test; %0d instructions retired; %0d load-use stalls; branch/jump flushes checked",
                     retire_count, stall_count);
        end
        $finish;
    end

    initial begin
        #30000;
        $display("FAIL: hazard/control watchdog timeout");
        $fatal(1);
    end
endmodule

`default_nettype wire
