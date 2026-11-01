`default_nettype none

// Five-stage, single-issue RV32I-subset core.
// Memory is combinational-read, edge-write, and has no wait-state response.
// A one-cycle load-use interlock and EX-stage forwarding are implemented.
module rv32i_core (
    input  wire         clk,
    input  wire         rst_n,
    output logic [31:0] imem_addr,
    input  wire [31:0]  imem_rdata,
    output logic [31:0] dmem_addr,
    output logic        dmem_read,
    output logic        dmem_write,
    output logic [3:0]  dmem_wstrb,
    output logic [31:0] dmem_wdata,
    input  wire [31:0]  dmem_rdata,
    output logic        retire_valid,
    output logic [31:0] retire_pc,
    output logic [31:0] retire_insn,
    output logic        retire_rd_we,
    output logic [4:0]  retire_rd,
    output logic [31:0] retire_rd_data,
    output logic        retire_store_we,
    output logic [31:0] retire_store_addr,
    output logic [3:0]  retire_store_wstrb,
    output logic [31:0] retire_store_wdata,
    output logic        stop,
    output logic [1:0]  stop_cause,
    output logic [31:0] stop_pc
);

    localparam logic [1:0] STOP_NONE       = 2'd0;
    localparam logic [1:0] STOP_ILLEGAL    = 2'd1;
    localparam logic [1:0] STOP_DATA_ALIGN = 2'd2;
    localparam logic [1:0] STOP_PC_ALIGN   = 2'd3;

    localparam logic [3:0] ALU_ADD  = 4'd0;
    localparam logic [3:0] ALU_SUB  = 4'd1;
    localparam logic [3:0] ALU_SLL  = 4'd2;
    localparam logic [3:0] ALU_SLT  = 4'd3;
    localparam logic [3:0] ALU_SLTU = 4'd4;
    localparam logic [3:0] ALU_XOR  = 4'd5;
    localparam logic [3:0] ALU_SRL  = 4'd6;
    localparam logic [3:0] ALU_SRA  = 4'd7;
    localparam logic [3:0] ALU_OR   = 4'd8;
    localparam logic [3:0] ALU_AND  = 4'd9;
    localparam logic [3:0] ALU_PASS = 4'd10;

    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_OPIMM  = 7'b0010011;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_OP     = 7'b0110011;
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_JAL    = 7'b1101111;

    logic [31:0] pc_f;
    logic ifid_valid;
    logic [31:0] ifid_pc, ifid_insn;

    logic idex_valid, idex_regwrite, idex_memread, idex_memwrite;
    logic idex_load_unsigned, idex_branch, idex_jal, idex_jalr;
    logic idex_illegal;
    logic idex_uses_rs1, idex_uses_rs2;
    logic [31:0] idex_pc, idex_insn, idex_a, idex_b, idex_imm;
    logic [4:0] idex_rs1, idex_rs2, idex_rd;
    logic [3:0] idex_alu_op;
    logic [2:0] idex_funct3;
    logic [1:0] idex_mem_size; // 0=byte, 1=halfword, 2=word

    logic exmem_valid, exmem_regwrite, exmem_memread, exmem_memwrite;
    logic exmem_load_unsigned, exmem_result_pc4;
    logic [31:0] exmem_pc, exmem_insn, exmem_result, exmem_store_data;
    logic [4:0] exmem_rd;
    logic [3:0] exmem_wstrb;

    logic memwb_valid, memwb_regwrite, memwb_store_we;
    logic [31:0] memwb_pc, memwb_insn, memwb_result;
    logic [4:0] memwb_rd;
    logic [31:0] memwb_store_addr, memwb_store_data;
    logic [3:0] memwb_store_wstrb;

    logic [31:0] regs [0:31];
    logic [31:0] dec_imm, dec_rs1_value, dec_rs2_value;
    logic [4:0] dec_rs1, dec_rs2, dec_rd;
    logic [3:0] dec_alu_op;
    logic [2:0] dec_funct3;
    logic [1:0] dec_mem_size;
    logic dec_regwrite, dec_memread, dec_memwrite;
    logic dec_load_unsigned, dec_branch, dec_jal, dec_jalr, dec_illegal;
    logic dec_uses_rs1, dec_uses_rs2;

    logic [31:0] ex_forward_a, ex_forward_b;
    logic [31:0] ex_alu_b, ex_result, ex_branch_target;
    logic ex_branch_taken, ex_redirect, ex_fault;
    logic load_use_stall;
    logic [1:0] ex_fault_cause;
    logic [3:0] ex_store_wstrb;
    logic [31:0] ex_store_wdata;
    logic [31:0] mem_load_value;

    function automatic logic [31:0] imm_i(input logic [31:0] insn);
        imm_i = {{20{insn[31]}}, insn[31:20]};
    endfunction

    function automatic logic [31:0] imm_s(input logic [31:0] insn);
        imm_s = {{20{insn[31]}}, insn[31:25], insn[11:7]};
    endfunction

    function automatic logic [31:0] imm_b(input logic [31:0] insn);
        imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
    endfunction

    function automatic logic [31:0] imm_u(input logic [31:0] insn);
        imm_u = {insn[31:12], 12'b0};
    endfunction

    function automatic logic [31:0] imm_j(input logic [31:0] insn);
        imm_j = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};
    endfunction

    assign imem_addr = pc_f;
    assign retire_valid = rst_n && memwb_valid;
    assign retire_pc = memwb_pc;
    assign retire_insn = memwb_insn;
    assign retire_rd_we = rst_n && memwb_valid && memwb_regwrite && (memwb_rd != 5'd0);
    assign retire_rd = memwb_rd;
    assign retire_rd_data = memwb_result;
    assign retire_store_we = rst_n && memwb_valid && memwb_store_we;
    assign retire_store_addr = memwb_store_addr;
    assign retire_store_wstrb = memwb_store_wstrb;
    assign retire_store_wdata = memwb_store_data;

    // Byte-enable memory requests are issued only by a valid MEM-stage slot.
    assign dmem_addr = exmem_result;
    assign dmem_read = rst_n && exmem_valid && exmem_memread && !stop;
    assign dmem_write = rst_n && exmem_valid && exmem_memwrite && !stop;
    assign dmem_wstrb = exmem_wstrb;
    assign dmem_wdata = exmem_store_data;

    always_comb begin
        dec_rs1 = ifid_insn[19:15];
        dec_rs2 = ifid_insn[24:20];
        dec_rd = ifid_insn[11:7];
        dec_imm = 32'b0;
        dec_alu_op = ALU_ADD;
        dec_funct3 = ifid_insn[14:12];
        dec_mem_size = 2'd2;
        dec_regwrite = 1'b0;
        dec_memread = 1'b0;
        dec_memwrite = 1'b0;
        dec_load_unsigned = 1'b0;
        dec_branch = 1'b0;
        dec_jal = 1'b0;
        dec_jalr = 1'b0;
        dec_illegal = 1'b1;
        dec_uses_rs1 = 1'b0;
        dec_uses_rs2 = 1'b0;

        case (ifid_insn[6:0])
            OP_OP: begin
                case (ifid_insn[14:12])
                    3'b000: begin
                        if (ifid_insn[31:25] == 7'b0000000) begin dec_alu_op=ALU_ADD; dec_illegal=0; end
                        else if (ifid_insn[31:25] == 7'b0100000) begin dec_alu_op=ALU_SUB; dec_illegal=0; end
                    end
                    3'b001: if (ifid_insn[31:25] == 7'b0000000) begin dec_alu_op=ALU_SLL; dec_illegal=0; end
                    3'b010: if (ifid_insn[31:25] == 7'b0000000) begin dec_alu_op=ALU_SLT; dec_illegal=0; end
                    3'b011: if (ifid_insn[31:25] == 7'b0000000) begin dec_alu_op=ALU_SLTU; dec_illegal=0; end
                    3'b100: if (ifid_insn[31:25] == 7'b0000000) begin dec_alu_op=ALU_XOR; dec_illegal=0; end
                    3'b101: begin
                        if (ifid_insn[31:25] == 7'b0000000) begin dec_alu_op=ALU_SRL; dec_illegal=0; end
                        else if (ifid_insn[31:25] == 7'b0100000) begin dec_alu_op=ALU_SRA; dec_illegal=0; end
                    end
                    3'b110: if (ifid_insn[31:25] == 7'b0000000) begin dec_alu_op=ALU_OR; dec_illegal=0; end
                    3'b111: if (ifid_insn[31:25] == 7'b0000000) begin dec_alu_op=ALU_AND; dec_illegal=0; end
                    default: dec_illegal=1'b1;
                endcase
                if (!dec_illegal) begin
                    dec_regwrite=1'b1;
                    dec_uses_rs1=1'b1;
                    dec_uses_rs2=1'b1;
                end
            end
            OP_OPIMM: begin
                dec_imm = imm_i(ifid_insn);
                case (ifid_insn[14:12])
                    3'b000: begin dec_alu_op=ALU_ADD; dec_illegal=0; end
                    3'b010: begin dec_alu_op=ALU_SLT; dec_illegal=0; end
                    3'b011: begin dec_alu_op=ALU_SLTU; dec_illegal=0; end
                    3'b100: begin dec_alu_op=ALU_XOR; dec_illegal=0; end
                    3'b110: begin dec_alu_op=ALU_OR; dec_illegal=0; end
                    3'b111: begin dec_alu_op=ALU_AND; dec_illegal=0; end
                    3'b001: if (ifid_insn[31:25] == 7'b0000000) begin dec_alu_op=ALU_SLL; dec_illegal=0; end
                    3'b101: begin
                        if (ifid_insn[31:25] == 7'b0000000) begin dec_alu_op=ALU_SRL; dec_illegal=0; end
                        else if (ifid_insn[31:25] == 7'b0100000) begin dec_alu_op=ALU_SRA; dec_illegal=0; end
                    end
                    default: dec_illegal=1'b1;
                endcase
                if (!dec_illegal) begin
                    dec_regwrite=1'b1;
                    dec_uses_rs1=1'b1;
                end
            end
            OP_LOAD: begin
                dec_imm = imm_i(ifid_insn);
                dec_memread = 1'b1;
                dec_regwrite = 1'b1;
                dec_uses_rs1 = 1'b1;
                case (ifid_insn[14:12])
                    3'b000: begin dec_mem_size=2'd0; dec_load_unsigned=0; dec_illegal=0; end
                    3'b001: begin dec_mem_size=2'd1; dec_load_unsigned=0; dec_illegal=0; end
                    3'b010: begin dec_mem_size=2'd2; dec_load_unsigned=0; dec_illegal=0; end
                    3'b100: begin dec_mem_size=2'd0; dec_load_unsigned=1; dec_illegal=0; end
                    3'b101: begin dec_mem_size=2'd1; dec_load_unsigned=1; dec_illegal=0; end
                    default: begin dec_memread=0; dec_regwrite=0; dec_illegal=1; end
                endcase
            end
            OP_STORE: begin
                dec_imm = imm_s(ifid_insn);
                dec_memwrite = 1'b1;
                dec_uses_rs1 = 1'b1;
                dec_uses_rs2 = 1'b1;
                case (ifid_insn[14:12])
                    3'b000: begin dec_mem_size=2'd0; dec_illegal=0; end
                    3'b001: begin dec_mem_size=2'd1; dec_illegal=0; end
                    3'b010: begin dec_mem_size=2'd2; dec_illegal=0; end
                    default: begin dec_memwrite=0; dec_illegal=1; end
                endcase
            end
            OP_BRANCH: begin
                dec_imm = imm_b(ifid_insn);
                dec_branch = 1'b1;
                dec_uses_rs1 = 1'b1;
                dec_uses_rs2 = 1'b1;
                if (ifid_insn[14:12] == 3'b000 || ifid_insn[14:12] == 3'b001 ||
                    ifid_insn[14:12] == 3'b100 || ifid_insn[14:12] == 3'b101 ||
                    ifid_insn[14:12] == 3'b110 || ifid_insn[14:12] == 3'b111)
                    dec_illegal=1'b0;
            end
            OP_JAL: begin
                dec_imm = imm_j(ifid_insn);
                dec_jal = 1'b1;
                dec_regwrite = 1'b1;
                dec_illegal = 1'b0;
            end
            OP_JALR: begin
                dec_imm = imm_i(ifid_insn);
                if (ifid_insn[14:12] == 3'b000) begin
                    dec_jalr=1'b1; dec_regwrite=1'b1; dec_illegal=1'b0; dec_uses_rs1=1'b1;
                end
            end
            OP_LUI: begin
                dec_imm=imm_u(ifid_insn); dec_alu_op=ALU_PASS;
                dec_regwrite=1'b1; dec_illegal=1'b0;
            end
            OP_AUIPC: begin
                dec_imm=imm_u(ifid_insn); dec_regwrite=1'b1; dec_illegal=1'b0;
            end
            default: dec_illegal=1'b1;
        endcase

        dec_rs1_value = (dec_rs1 == 0) ? 32'b0 : regs[dec_rs1];
        dec_rs2_value = (dec_rs2 == 0) ? 32'b0 : regs[dec_rs2];
        if (memwb_valid && memwb_regwrite && (memwb_rd != 0) && (memwb_rd == dec_rs1))
            dec_rs1_value = memwb_result;
        if (memwb_valid && memwb_regwrite && (memwb_rd != 0) && (memwb_rd == dec_rs2))
            dec_rs2_value = memwb_result;
    end

    always_comb begin
        ex_forward_a = idex_a;
        ex_forward_b = idex_b;
        if (idex_uses_rs1 && (idex_rs1 != 0) && exmem_valid && exmem_regwrite &&
            !exmem_memread && (exmem_rd == idex_rs1))
            ex_forward_a = exmem_result;
        else if (idex_uses_rs1 && (idex_rs1 != 0) && memwb_valid && memwb_regwrite &&
                 (memwb_rd == idex_rs1))
            ex_forward_a = memwb_result;

        if (idex_uses_rs2 && (idex_rs2 != 0) && exmem_valid && exmem_regwrite &&
            !exmem_memread && (exmem_rd == idex_rs2))
            ex_forward_b = exmem_result;
        else if (idex_uses_rs2 && (idex_rs2 != 0) && memwb_valid && memwb_regwrite &&
                 (memwb_rd == idex_rs2))
            ex_forward_b = memwb_result;
    end

    assign load_use_stall = ifid_valid && idex_valid && idex_memread && (idex_rd != 0) &&
                            ((dec_uses_rs1 && (dec_rs1 == idex_rd)) ||
                             (dec_uses_rs2 && (dec_rs2 == idex_rd)));

    assign ex_alu_b = (idex_memread || idex_memwrite || idex_jal || idex_jalr ||
                       (idex_insn[6:0] == OP_OPIMM) ||
                       (idex_insn[6:0] == OP_LUI) || (idex_insn[6:0] == OP_AUIPC)) ? idex_imm : ex_forward_b;

    always_comb begin
        case (idex_alu_op)
            ALU_ADD:  ex_result = ex_forward_a + ex_alu_b;
            ALU_SUB:  ex_result = ex_forward_a - ex_alu_b;
            ALU_SLL:  ex_result = ex_forward_a << ex_alu_b[4:0];
            ALU_SLT:  ex_result = ($signed(ex_forward_a) < $signed(ex_alu_b)) ? 32'd1 : 32'd0;
            ALU_SLTU: ex_result = (ex_forward_a < ex_alu_b) ? 32'd1 : 32'd0;
            ALU_XOR:  ex_result = ex_forward_a ^ ex_alu_b;
            ALU_SRL:  ex_result = ex_forward_a >> ex_alu_b[4:0];
            ALU_SRA:  ex_result = $signed(ex_forward_a) >>> ex_alu_b[4:0];
            ALU_OR:   ex_result = ex_forward_a | ex_alu_b;
            ALU_AND:  ex_result = ex_forward_a & ex_alu_b;
            ALU_PASS: ex_result = ex_alu_b;
            default:  ex_result = 32'b0;
        endcase
        if (idex_insn[6:0] == OP_AUIPC) ex_result = idex_pc + idex_imm;
        if (idex_jal || idex_jalr) ex_result = idex_pc + 32'd4;

        ex_branch_taken = 1'b0;
        case (idex_funct3)
            3'b000: ex_branch_taken = (ex_forward_a == ex_forward_b);
            3'b001: ex_branch_taken = (ex_forward_a != ex_forward_b);
            3'b100: ex_branch_taken = ($signed(ex_forward_a) < $signed(ex_forward_b));
            3'b101: ex_branch_taken = ($signed(ex_forward_a) >= $signed(ex_forward_b));
            3'b110: ex_branch_taken = (ex_forward_a < ex_forward_b);
            3'b111: ex_branch_taken = (ex_forward_a >= ex_forward_b);
            default: ex_branch_taken = 1'b0;
        endcase

        ex_branch_target = idex_pc + idex_imm;
        if (idex_jalr) ex_branch_target = (ex_forward_a + idex_imm) & 32'hffff_fffe;
        ex_redirect = idex_valid && !idex_illegal &&
                      ((idex_branch && ex_branch_taken) || idex_jal || idex_jalr);

        ex_store_wstrb = 4'b0000;
        ex_store_wdata = 32'b0;
        case (idex_mem_size)
            2'd0: begin
                ex_store_wstrb = 4'b0001 << ex_result[1:0];
                ex_store_wdata = {24'b0, ex_forward_b[7:0]} << (8 * ex_result[1:0]);
            end
            2'd1: begin
                ex_store_wstrb = 4'b0011 << {ex_result[1],1'b0};
                ex_store_wdata = {16'b0, ex_forward_b[15:0]} << (16 * ex_result[1]);
            end
            default: begin
                ex_store_wstrb = 4'b1111;
                ex_store_wdata = ex_forward_b;
            end
        endcase

        ex_fault = 1'b0;
        ex_fault_cause = STOP_NONE;
        if (idex_valid && idex_illegal) begin
            ex_fault = 1'b1;
            ex_fault_cause = STOP_ILLEGAL;
        end else if (idex_valid && (idex_memread || idex_memwrite) &&
                     ((idex_mem_size == 2'd1 && ex_result[0]) ||
                      (idex_mem_size == 2'd2 && |ex_result[1:0]))) begin
            ex_fault = 1'b1;
            ex_fault_cause = STOP_DATA_ALIGN;
        end else if (ex_redirect && (|ex_branch_target[1:0])) begin
            ex_fault = 1'b1;
            ex_fault_cause = STOP_PC_ALIGN;
        end
    end

    always_comb begin
        mem_load_value = 32'b0;
        case (exmem_insn[14:12])
            3'b000: begin // LB
                case (exmem_result[1:0])
                    2'd0: mem_load_value = {{24{dmem_rdata[7]}}, dmem_rdata[7:0]};
                    2'd1: mem_load_value = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                    2'd2: mem_load_value = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                    default: mem_load_value = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
                endcase
            end
            3'b100: begin // LBU
                case (exmem_result[1:0])
                    2'd0: mem_load_value = {24'b0, dmem_rdata[7:0]};
                    2'd1: mem_load_value = {24'b0, dmem_rdata[15:8]};
                    2'd2: mem_load_value = {24'b0, dmem_rdata[23:16]};
                    default: mem_load_value = {24'b0, dmem_rdata[31:24]};
                endcase
            end
            3'b001: mem_load_value = exmem_result[1] ?
                                      {{16{dmem_rdata[31]}}, dmem_rdata[31:16]} :
                                      {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
            3'b101: mem_load_value = exmem_result[1] ?
                                      {16'b0, dmem_rdata[31:16]} :
                                      {16'b0, dmem_rdata[15:0]};
            3'b010: mem_load_value = dmem_rdata; // LW
            default: mem_load_value = 32'b0;
        endcase
    end

    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_f <= 32'b0;
            ifid_valid <= 1'b0;
            ifid_pc <= 32'b0;
            ifid_insn <= 32'h0000_0013;
            idex_valid <= 1'b0;
            idex_pc <= 32'b0;
            idex_insn <= 32'h0000_0013;
            idex_a <= 32'b0;
            idex_b <= 32'b0;
            idex_imm <= 32'b0;
            idex_rs1 <= 5'b0;
            idex_rs2 <= 5'b0;
            idex_rd <= 5'b0;
            idex_alu_op <= ALU_ADD;
            idex_funct3 <= 3'b0;
            idex_mem_size <= 2'd2;
            idex_regwrite <= 1'b0;
            idex_memread <= 1'b0;
            idex_memwrite <= 1'b0;
            idex_load_unsigned <= 1'b0;
            idex_branch <= 1'b0;
            idex_jal <= 1'b0;
            idex_jalr <= 1'b0;
            idex_illegal <= 1'b0;
            idex_uses_rs1 <= 1'b0;
            idex_uses_rs2 <= 1'b0;
            exmem_valid <= 1'b0;
            exmem_regwrite <= 1'b0;
            exmem_memread <= 1'b0;
            exmem_memwrite <= 1'b0;
            exmem_load_unsigned <= 1'b0;
            exmem_result_pc4 <= 1'b0;
            exmem_pc <= 32'b0;
            exmem_insn <= 32'h0000_0013;
            exmem_result <= 32'b0;
            exmem_store_data <= 32'b0;
            exmem_rd <= 5'b0;
            exmem_wstrb <= 4'b0;
            memwb_valid <= 1'b0;
            memwb_regwrite <= 1'b0;
            memwb_store_we <= 1'b0;
            memwb_pc <= 32'b0;
            memwb_insn <= 32'h0000_0013;
            memwb_result <= 32'b0;
            memwb_rd <= 5'b0;
            memwb_store_addr <= 32'b0;
            memwb_store_data <= 32'b0;
            memwb_store_wstrb <= 4'b0;
            stop <= 1'b0;
            stop_cause <= STOP_NONE;
            stop_pc <= 32'b0;
            for (i=0; i<32; i=i+1) regs[i] <= 32'b0;
        end else begin
            if (memwb_valid && memwb_regwrite && (memwb_rd != 0))
                regs[memwb_rd] <= memwb_result;
            regs[0] <= 32'b0;

            // Old EX/MEM slot advances to WB even on a fault, allowing older
            // instructions to drain. Faulting and younger slots are discarded.
            memwb_valid <= exmem_valid;
            memwb_regwrite <= exmem_regwrite;
            memwb_store_we <= exmem_valid && exmem_memwrite;
            memwb_pc <= exmem_pc;
            memwb_insn <= exmem_insn;
            memwb_rd <= exmem_rd;
            memwb_result <= exmem_memread ? mem_load_value :
                            (exmem_result_pc4 ? (exmem_pc + 32'd4) : exmem_result);
            memwb_store_addr <= exmem_result;
            memwb_store_data <= exmem_store_data;
            memwb_store_wstrb <= exmem_wstrb;

            if (ex_fault && !stop) begin
                stop <= 1'b1;
                stop_cause <= ex_fault_cause;
                stop_pc <= idex_pc;
                ifid_valid <= 1'b0;
                idex_valid <= 1'b0;
                exmem_valid <= 1'b0;
                exmem_regwrite <= 1'b0;
                exmem_memread <= 1'b0;
                exmem_memwrite <= 1'b0;
                exmem_wstrb <= 4'b0;
                pc_f <= pc_f;
            end else if (stop) begin
                ifid_valid <= 1'b0;
                idex_valid <= 1'b0;
                exmem_valid <= 1'b0;
                exmem_regwrite <= 1'b0;
                exmem_memread <= 1'b0;
                exmem_memwrite <= 1'b0;
                exmem_wstrb <= 4'b0;
            end else begin
                exmem_valid <= idex_valid;
                exmem_regwrite <= idex_regwrite;
                exmem_memread <= idex_memread;
                exmem_memwrite <= idex_memwrite;
                exmem_load_unsigned <= idex_load_unsigned;
                exmem_result_pc4 <= idex_jal || idex_jalr;
                exmem_pc <= idex_pc;
                exmem_insn <= idex_insn;
                exmem_result <= ex_result;
                exmem_store_data <= ex_store_wdata;
                exmem_rd <= idex_rd;
                exmem_wstrb <= idex_memwrite ? ex_store_wstrb : 4'b0;

                if (ex_redirect) begin
                    ifid_valid <= 1'b0;
                    idex_valid <= 1'b0;
                    pc_f <= ex_branch_target;
                end else if (load_use_stall) begin
                    // Hold fetch/decode and insert one bubble while the load
                    // advances from EX into MEM. The consumer re-enters EX
                    // after its result is available in MEM/WB.
                    idex_valid <= 1'b0;
                end else begin
                    idex_valid <= ifid_valid;
                    idex_pc <= ifid_pc;
                    idex_insn <= ifid_insn;
                    idex_rs1 <= dec_rs1;
                    idex_rs2 <= dec_rs2;
                    idex_a <= dec_rs1_value;
                    idex_b <= dec_rs2_value;
                    idex_imm <= dec_imm;
                    idex_rd <= dec_rd;
                    idex_alu_op <= dec_alu_op;
                    idex_funct3 <= dec_funct3;
                    idex_mem_size <= dec_mem_size;
                    idex_regwrite <= dec_regwrite;
                    idex_memread <= dec_memread;
                    idex_memwrite <= dec_memwrite;
                    idex_load_unsigned <= dec_load_unsigned;
                    idex_branch <= dec_branch;
                    idex_jal <= dec_jal;
                    idex_jalr <= dec_jalr;
                    idex_illegal <= dec_illegal;
                    idex_uses_rs1 <= dec_uses_rs1;
                    idex_uses_rs2 <= dec_uses_rs2;
                    ifid_valid <= 1'b1;
                    ifid_pc <= pc_f;
                    ifid_insn <= imem_rdata;
                    pc_f <= pc_f + 32'd4;
                end
            end
        end
    end

`ifdef FORMAL
    // Verification-only safety properties; omitted from normal synthesis and
    // simulation builds. The formal harness supplies an initial reset window.
    logic formal_past_valid;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            formal_past_valid <= 1'b0;
            assert(!dmem_read && !dmem_write && !retire_rd_we && !retire_store_we);
        end else begin
            formal_past_valid <= 1'b1;
            assert(regs[0] == 32'b0);
            assert(!retire_rd_we || (retire_valid && retire_rd != 5'd0));
            assert(!dmem_read || (exmem_valid && exmem_memread && !stop));
            assert(!dmem_write || (exmem_valid && exmem_memwrite && !stop));

            // Forwarding must choose the youngest available writer. A load in
            // EX/MEM is deliberately skipped because its data is not ready.
            if (idex_valid && idex_uses_rs1 && idex_rs1 != 0) begin
                if (exmem_valid && exmem_regwrite && !exmem_memread && exmem_rd == idex_rs1)
                    assert(ex_forward_a == exmem_result);
                else if (memwb_valid && memwb_regwrite && memwb_rd == idex_rs1)
                    assert(ex_forward_a == memwb_result);
            end
            if (idex_valid && idex_uses_rs2 && idex_rs2 != 0) begin
                if (exmem_valid && exmem_regwrite && !exmem_memread && exmem_rd == idex_rs2)
                    assert(ex_forward_b == exmem_result);
                else if (memwb_valid && memwb_regwrite && memwb_rd == idex_rs2)
                    assert(ex_forward_b == memwb_result);
            end

            if (dmem_read || dmem_write) begin
                case (exmem_insn[14:12])
                    3'b000, 3'b100: assert(1'b1); // byte accesses are lane-aligned
                    3'b001, 3'b101: assert(!dmem_addr[0]);
                    3'b010: assert(dmem_addr[1:0] == 2'b00);
                    default: assert(1'b0);
                endcase
            end

            if (formal_past_valid && $past(load_use_stall)) begin
                assert(pc_f == $past(pc_f));
                assert(ifid_valid == $past(ifid_valid));
                assert(ifid_pc == $past(ifid_pc));
                assert(ifid_insn == $past(ifid_insn));
                assert(!idex_valid);
            end

            if (formal_past_valid && $past(ex_redirect && !ex_fault)) begin
                assert(pc_f == $past(ex_branch_target));
                assert(!ifid_valid);
                assert(!idex_valid);
            end
        end
    end
`endif

endmodule

`default_nettype wire
