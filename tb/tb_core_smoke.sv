`timescale 1ns/1ps
`default_nettype none

module tb_core_smoke;
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
    logic exp_we [0:255];
    logic [4:0] exp_rd [0:255];
    logic [31:0] exp_value [0:255];
    logic exp_store [0:255];
    logic [31:0] exp_store_addr [0:255];
    logic [3:0] exp_store_strb [0:255];
    logic [31:0] exp_store_data [0:255];
    integer program_count = 0;
    integer retire_count = 0;
    integer failure_count = 0;
    integer k;
    integer byte_base;

    always #5 clk = ~clk;

    always_comb begin
        imem_rdata = imem[imem_addr[9:2]];
        byte_base = dmem_addr[11:2] * 4;
        dmem_rdata = {dmem[byte_base+3], dmem[byte_base+2],
                      dmem[byte_base+1], dmem[byte_base]};
    end

    always @(posedge clk) begin
        if (rst_n && dmem_write) begin
            for (integer lane=0; lane<4; lane=lane+1) begin
                if (dmem_wstrb[lane])
                    dmem[byte_base+lane] <= dmem_wdata[8*lane +: 8];
            end
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

    function automatic [31:0] enc_i(
        input integer imm, input integer rs1, input integer funct3,
        input integer rd, input integer opcode
    );
        enc_i = {imm[11:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    endfunction

    function automatic [31:0] enc_r(
        input integer funct7, input integer rs2, input integer rs1,
        input integer funct3, input integer rd, input integer opcode
    );
        enc_r = {funct7[6:0], rs2[4:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    endfunction

    function automatic [31:0] enc_s(
        input integer imm, input integer rs2, input integer rs1,
        input integer funct3, input integer opcode
    );
        enc_s = {imm[11:5], rs2[4:0], rs1[4:0], funct3[2:0], imm[4:0], opcode[6:0]};
    endfunction

    function automatic [31:0] enc_u(input integer imm20, input integer rd, input integer opcode);
        enc_u = {imm20[19:0], rd[4:0], opcode[6:0]};
    endfunction

    task automatic emit(
        input logic [31:0] insn,
        input logic writes_rd,
        input logic [4:0] rd,
        input logic [31:0] value,
        input logic stores,
        input logic [31:0] store_addr,
        input logic [3:0] store_strb,
        input logic [31:0] store_data
    );
        begin
            imem[program_count] = insn;
            exp_we[program_count] = writes_rd;
            exp_rd[program_count] = rd;
            exp_value[program_count] = value;
            exp_store[program_count] = stores;
            exp_store_addr[program_count] = store_addr;
            exp_store_strb[program_count] = store_strb;
            exp_store_data[program_count] = store_data;
            program_count = program_count + 1;
        end
    endtask

    task automatic emit_nop;
        begin
            emit(enc_i(0,0,0,0,7'b0010011), 1'b0, 5'd0, 32'b0,
                 1'b0, 32'b0, 4'b0, 32'b0);
        end
    endtask

    always @(posedge clk) begin
        if (retire_valid) begin
            if (retire_count >= program_count) begin
                $display("FAIL: unexpected retirement pc=%08x", retire_pc);
                failure_count = failure_count + 1;
            end else begin
                if (retire_pc !== (retire_count * 4)) begin
                    $display("FAIL: retirement order expected pc=%08x got=%08x",
                             retire_count * 4, retire_pc);
                    failure_count = failure_count + 1;
                end
                if (retire_rd_we !== exp_we[retire_count]) begin
                    $display("FAIL: pc=%08x rd_we expected=%b got=%b",
                             retire_pc, exp_we[retire_count], retire_rd_we);
                    failure_count = failure_count + 1;
                end
                if (exp_we[retire_count] &&
                    (retire_rd !== exp_rd[retire_count] || retire_rd_data !== exp_value[retire_count])) begin
                    $display("FAIL: pc=%08x rd expected x%0d=%08x got x%0d=%08x",
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
                    $display("FAIL: pc=%08x store address/strobe/data mismatch", retire_pc);
                    failure_count = failure_count + 1;
                end
            end
            retire_count = retire_count + 1;
        end
    end

    initial begin
        for (k=0; k<256; k=k+1) begin
            imem[k] = 32'h0000_0013;
            exp_we[k] = 1'b0;
            exp_rd[k] = 5'd0;
            exp_value[k] = 32'b0;
            exp_store[k] = 1'b0;
            exp_store_addr[k] = 32'b0;
            exp_store_strb[k] = 4'b0;
            exp_store_data[k] = 32'b0;
        end
        for (k=0; k<4096; k=k+1) dmem[k] = 8'b0;

        // Independent setup writes, followed by spacing because interlocks are M3.
        emit(enc_i(8,0,0,1,7'b0010011), 1, 1, 8, 0, 0, 0, 0);
        emit(enc_i(-3,0,0,2,7'b0010011), 1, 2, 32'hffff_fffd, 0, 0, 0, 0);
        emit_nop(); emit_nop(); emit_nop();

        emit(enc_r(0,2,1,0,3,7'b0110011), 1, 3, 32'd5, 0, 0, 0, 0); // ADD
        emit(enc_r(7'b0100000,2,1,0,4,7'b0110011), 1, 4, 32'd11, 0, 0, 0, 0); // SUB
        emit(enc_r(0,2,1,4,5,7'b0110011), 1, 5, 32'hffff_fff5, 0, 0, 0, 0); // XOR
        emit(enc_r(0,2,1,6,6,7'b0110011), 1, 6, 32'hffff_fffd, 0, 0, 0, 0); // OR
        emit(enc_r(0,2,1,7,7,7'b0110011), 1, 7, 32'd8, 0, 0, 0, 0); // AND
        emit(enc_r(0,2,1,2,8,7'b0110011), 1, 8, 32'd0, 0, 0, 0, 0); // SLT: 8 < -3 is false
        emit(enc_r(0,2,1,3,9,7'b0110011), 1, 9, 32'd1, 0, 0, 0, 0); // SLTU: 8 < 0xffff_fffd
        emit(enc_r(0,2,1,1,10,7'b0110011), 1, 10, 32'd0, 0, 0, 0, 0); // SLL
        emit(enc_r(7'b0100000,2,1,5,11,7'b0110011), 1, 11, 32'd0, 0, 0, 0, 0); // SRA
        emit(enc_r(0,2,1,5,12,7'b0110011), 1, 12, 32'd0, 0, 0, 0, 0); // SRL
        emit(enc_r(0,2,1,1,13,7'b0110011), 1, 13, 32'd0, 0, 0, 0, 0); // SLL (low five shift bits=29)
        emit(enc_r(0,2,1,6,14,7'b0110011), 1, 14, 32'hffff_fffd, 0, 0, 0, 0); // OR repeat
        emit(enc_r(0,2,1,7,15,7'b0110011), 1, 15, 32'd8, 0, 0, 0, 0); // AND repeat

        emit(enc_i(-4,1,0,16,7'b0010011), 1, 16, 32'd4, 0, 0, 0, 0); // ADDI
        emit(enc_i(1,2,2,17,7'b0010011), 1, 17, 32'd1, 0, 0, 0, 0); // SLTI
        emit(enc_i(-1,2,3,18,7'b0010011), 1, 18, 32'd1, 0, 0, 0, 0); // SLTIU
        emit(enc_i(255,2,4,19,7'b0010011), 1, 19, 32'hffff_ff02, 0, 0, 0, 0); // XORI
        emit(enc_i(16'h155,0,6,20,7'b0010011), 1, 20, 32'h155, 0, 0, 0, 0); // ORI
        emit(enc_i(15,2,7,21,7'b0010011), 1, 21, 32'd13, 0, 0, 0, 0); // ANDI
        emit(enc_i(3,1,1,22,7'b0010011), 1, 22, 32'd64, 0, 0, 0, 0); // SLLI
        emit(enc_i(1,1,5,23,7'b0010011), 1, 23, 32'd4, 0, 0, 0, 0); // SRLI
        emit(enc_i(12'h401,2,5,24,7'b0010011), 1, 24, 32'hffff_fffe, 0, 0, 0, 0); // SRAI
        emit(enc_u(20'h12345,25,7'b0110111), 1, 25, 32'h1234_5000, 0, 0, 0, 0); // LUI
        emit(enc_u(1,26,7'b0010111), 1, 26, (program_count*4)+32'h1000, 0, 0, 0, 0); // AUIPC

        emit(enc_s(64,2,0,0,7'b0100011), 0, 0, 0, 1, 64, 4'b0001, 32'h0000_00fd); // SB
        emit(enc_s(66,2,0,1,7'b0100011), 0, 0, 0, 1, 66, 4'b1100, 32'hfffd_0000); // SH
        emit(enc_s(68,2,0,2,7'b0100011), 0, 0, 0, 1, 68, 4'b1111, 32'hffff_fffd); // SW
        emit(enc_i(64,0,0,27,7'b0000011), 1, 27, 32'hffff_fffd, 0, 0, 0, 0); // LB
        emit(enc_i(64,0,4,28,7'b0000011), 1, 28, 32'h0000_00fd, 0, 0, 0, 0); // LBU
        emit(enc_i(66,0,1,29,7'b0000011), 1, 29, 32'hffff_fffd, 0, 0, 0, 0); // LH
        emit(enc_i(66,0,5,30,7'b0000011), 1, 30, 32'h0000_fffd, 0, 0, 0, 0); // LHU
        emit(enc_i(68,0,2,31,7'b0000011), 1, 31, 32'hffff_fffd, 0, 0, 0, 0); // LW

        imem[program_count] = 32'h0000_0000; // Unsupported encoding ends the smoke program.

        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        wait (stop === 1'b1);
        repeat (4) @(posedge clk);
        #1;
        if (stop_cause !== 2'd1 || stop_pc !== program_count*4) begin
            $display("FAIL: expected illegal stop pc=%08x cause=1 got pc=%08x cause=%0d",
                     program_count*4, stop_pc, stop_cause);
            failure_count = failure_count + 1;
        end
        if (retire_count != program_count) begin
            $display("FAIL: expected %0d retirements, observed %0d", program_count, retire_count);
            failure_count = failure_count + 1;
        end
        if (dmem[64] !== 8'hfd || dmem[66] !== 8'hfd || dmem[67] !== 8'hff ||
            dmem[68] !== 8'hfd || dmem[69] !== 8'hff || dmem[70] !== 8'hff || dmem[71] !== 8'hff) begin
            $display("FAIL: byte-addressed memory contents mismatch");
            failure_count = failure_count + 1;
        end
        if (failure_count != 0) begin
            $display("FAIL: basic RV32I smoke test; %0d failure(s)", failure_count);
            $fatal(1);
        end else begin
            $display("PASS: basic RV32I smoke test; %0d instructions retired; illegal stop checked", retire_count);
        end
        $finish;
    end

    initial begin
        #20000;
        $display("FAIL: watchdog timeout");
        $fatal(1);
    end
endmodule

`default_nettype wire
