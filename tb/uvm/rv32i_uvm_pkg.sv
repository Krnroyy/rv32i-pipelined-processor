`timescale 1ns/1ps
`default_nettype none

package rv32i_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    function automatic bit [31:0] enc_r(input bit [6:0] funct7, input bit [4:0] rs2,
                                        input bit [4:0] rs1, input bit [2:0] funct3,
                                        input bit [4:0] rd);
        enc_r = {funct7,rs2,rs1,funct3,rd,7'b0110011};
    endfunction

    function automatic bit [31:0] enc_i(input bit [11:0] imm, input bit [4:0] rs1,
                                        input bit [2:0] funct3, input bit [4:0] rd,
                                        input bit [6:0] opcode=7'b0010011);
        enc_i = {imm,rs1,funct3,rd,opcode};
    endfunction

    function automatic bit [31:0] enc_b(input integer offset, input bit [4:0] rs2,
                                        input bit [4:0] rs1, input bit [2:0] funct3);
        bit [12:0] imm;
        imm=offset;
        enc_b = {imm[12],imm[10:5],rs2,rs1,funct3,imm[4:1],imm[11],7'b1100011};
    endfunction

    function automatic bit [31:0] enc_s(input bit [11:0] imm, input bit [4:0] rs2,
                                        input bit [4:0] rs1, input bit [2:0] funct3);
        enc_s = {imm[11:5],rs2,rs1,funct3,imm[4:0],7'b0100011};
    endfunction

    function automatic bit [31:0] enc_j(input integer offset, input bit [4:0] rd);
        bit [20:0] imm;
        imm=offset;
        enc_j = {imm[20],imm[10:1],imm[11],imm[19:12],rd,7'b1101111};
    endfunction

    function automatic bit [31:0] enc_u(input bit [19:0] imm, input bit [4:0] rd,
                                        input bit [6:0] opcode);
        enc_u = {imm,rd,opcode};
    endfunction

    // Spell out sign fill instead of relying on simulator signed-expression
    // sizing rules in a ternary shift expression.
    function automatic bit [31:0] model_sra(input bit [31:0] value,
                                             input bit [4:0] amount);
        bit [31:0] sign_fill;
        bit [5:0] shift_fill;
        sign_fill=32'b0;
        if (value[31] && amount!=0) begin
            shift_fill=6'd32-{1'b0,amount};
            sign_fill=32'hffff_ffff << shift_fill;
        end
        model_sra=(value >> amount) | sign_fill;
    endfunction

    class rv32i_program_item extends uvm_sequence_item;
        rand bit [2:0] opclass; // R/I/load/store/branch/JAL
        rand bit [4:0] rd, rs1, rs2;
        rand bit [2:0] funct3;
        rand bit [6:0] funct7;
        rand bit [11:0] imm;
        bit [31:0] insn;
        bit last;

        constraint legal_fields {
            opclass inside {[0:5]};
            rd inside {[1:15]};
            rs1 inside {[0:15]};
            rs2 inside {[0:15]};
            if (!(opclass == 1 && funct3 == 5 && funct7 == 7'b0100000)) imm inside {[0:255]};
            if (opclass == 0) {
                if (funct3 == 0 || funct3 == 5) funct7 inside {7'b0000000,7'b0100000};
                else funct7 == 7'b0000000;
            }
            if (opclass == 1) {
                if (funct3 == 1) { funct7 == 0; imm[11:5] == 0; }
                else if (funct3 == 5) { funct7 inside {7'b0000000,7'b0100000}; imm[11:5] == funct7; }
                else funct7 == 0;
            }
            if (opclass == 2) {
                funct3 inside {3'b000,3'b001,3'b010,3'b100,3'b101};
                if (funct3 inside {3'b001,3'b101}) imm[0] == 0;
                if (funct3 == 3'b010) imm[1:0] == 0;
            }
            if (opclass == 3) {
                funct3 inside {3'b000,3'b001,3'b010};
                if (funct3 == 3'b001) imm[0] == 0;
                if (funct3 == 3'b010) imm[1:0] == 0;
            }
            if (opclass == 4) funct3 inside {3'b000,3'b001,3'b100,3'b101,3'b110,3'b111};
        }

        `uvm_object_utils(rv32i_program_item)
        function new(string name="rv32i_program_item"); super.new(name); endfunction
    endclass

    class rv32i_retire_item extends uvm_sequence_item;
        bit [31:0] pc, insn, rd_data, store_addr, store_data;
        bit [4:0] rd;
        bit rd_we, store_we;
        bit [3:0] store_strb;
        `uvm_object_utils(rv32i_retire_item)
        function new(string name="rv32i_retire_item"); super.new(name); endfunction
    endclass

    class rv32i_random_sequence extends uvm_sequence #(rv32i_program_item);
        `uvm_object_utils(rv32i_random_sequence)
        int unsigned word_index;
        function new(string name="rv32i_random_sequence"); super.new(name); endfunction

        task automatic put_word(bit [31:0] word);
            rv32i_program_item item;
            item = rv32i_program_item::type_id::create("item");
            start_item(item);
            item.insn = word;
            item.last = 0;
            finish_item(item);
            word_index++;
        endtask

        task automatic branch_case(input bit [2:0] funct3, input bit [4:0] rs1,
                                   input bit [4:0] rs2);
            put_word(enc_b(8,rs2,rs1,funct3));
            // A taken branch must flush the first write; both paths converge
            // on the second write, making the sequence deterministic.
            put_word(enc_i(12'd111,5'd0,3'b000,5'd23));
            put_word(enc_i(12'd222,5'd0,3'b000,5'd23));
        endtask

        task body();
            rv32i_program_item item;
            int n;
            int unsigned jalr_target;
            word_index=0;
            // Directed dependency prefix is checked by the same model/scoreboard.
            put_word({12'd5,5'd0,3'b000,5'd1,7'b0010011}); // addi x1,x0,5
            put_word({12'd9,5'd1,3'b000,5'd0,7'b0010011}); // attempted x0 write
            put_word({12'd1,5'd0,3'b000,5'd17,7'b0010011}); // verify x0 read is zero
            put_word({12'd1,5'd1,3'b000,5'd2,7'b0010011}); // addi x2,x1,1
            put_word({7'd0,5'd2,5'd2,3'b000,5'd3,7'b0110011}); // add x3,x2,x2: EX/MEM on both ports
            put_word({12'd3,5'd0,3'b000,5'd20,7'b0010011});
            put_word({12'd4,5'd0,3'b000,5'd21,7'b0010011});
            put_word({7'd0,5'd20,5'd20,3'b000,5'd22,7'b0110011}); // MEM/WB on both ports
            put_word({7'd4,5'd3,5'd0,3'b010,5'd0,7'b0100011}); // sw x3,128(x0)
            put_word({12'd128,5'd0,3'b010,5'd4,7'b0000011}); // lw x4,128(x0)
            put_word({12'd1,5'd4,3'b000,5'd5,7'b0010011}); // addi x5,x4,1
            put_word({1'b0,6'b0,5'd1,5'd1,3'b000,4'b0100,1'b0,7'b1100011}); // beq x1,x1,+8
            put_word({7'd4,5'd3,5'd0,3'b010,5'd0,7'b0100011}); // wrong-path sw, must flush
            put_word({12'd7,5'd0,3'b000,5'd6,7'b0010011}); // branch target
            put_word({1'b0,6'b0,5'd1,5'd1,3'b001,4'b0100,1'b0,7'b1100011}); // bne x1,x1,+8 (untaken)
            put_word({12'd1,5'd0,3'b000,5'd7,7'b0010011});
            put_word({12'd2,5'd0,3'b000,5'd8,7'b0010011});
            put_word({1'b0,10'b0000000100,1'b0,8'b0,5'd9,7'b1101111}); // jal x9,+8
            put_word({12'd99,5'd0,3'b000,5'd10,7'b0010011}); // wrong-path register write
            put_word({12'd2,5'd0,3'b000,5'd11,7'b0010011}); // jump target
            put_word({1'b0,6'b0,5'd1,5'd0,3'b110,4'b0100,1'b0,7'b1100011}); // bltu x0,x1,+8
            put_word({12'd99,5'd0,3'b000,5'd24,7'b0010011}); // wrong-path register write
            put_word({12'd3,5'd0,3'b000,5'd24,7'b0010011}); // branch target
            put_word({7'd4,5'd3,5'd0,3'b000,5'd1,7'b0100011}); // sb x3,129(x0)
            put_word({7'd4,5'd3,5'd0,3'b001,5'd2,7'b0100011}); // sh x3,130(x0)
            put_word({7'd4,5'd3,5'd0,3'b010,5'd4,7'b0100011}); // sw x3,132(x0)
            put_word({12'd129,5'd0,3'b000,5'd12,7'b0000011}); // lb
            put_word({12'd129,5'd0,3'b100,5'd13,7'b0000011}); // lbu
            put_word({12'd130,5'd0,3'b001,5'd14,7'b0000011}); // lh
            put_word({12'd130,5'd0,3'b101,5'd15,7'b0000011}); // lhu
            put_word({12'd132,5'd0,3'b010,5'd16,7'b0000011}); // lw
            put_word(enc_s(12'd136,5'd16,5'd0,3'b010)); // load-to-store-data interlock
            put_word({12'd132,5'd0,3'b010,5'd16,7'b0000011});
            put_word(enc_b(8,5'd16,5'd16,3'b000)); // load-to-taken-branch interlock
            put_word(enc_i(12'd111,5'd0,3'b000,5'd23)); // wrong path
            put_word(enc_i(12'd222,5'd0,3'b000,5'd23)); // branch target
            put_word({12'd132,5'd0,3'b010,5'd16,7'b0000011});
            put_word(enc_b(8,5'd16,5'd16,3'b001)); // load-to-untaken-branch interlock
            put_word(enc_i(12'd111,5'd0,3'b000,5'd23));
            put_word(enc_i(12'd222,5'd0,3'b000,5'd23));

            // Explicitly exercise all remaining arithmetic and immediate
            // operations through the same retirement reference scoreboard.
            put_word(enc_i(12'hfe0,5'd0,3'b000,5'd18)); // addi x18,x0,-32
            put_word(enc_r(7'b0000000,5'd2,5'd1,3'b000,5'd25)); // ADD
            put_word(enc_r(7'b0100000,5'd1,5'd2,3'b000,5'd26)); // SUB
            put_word(enc_r(7'b0000000,5'd2,5'd1,3'b001,5'd27)); // SLL
            put_word(enc_r(7'b0000000,5'd2,5'd1,3'b010,5'd28)); // SLT
            put_word(enc_r(7'b0000000,5'd2,5'd1,3'b011,5'd29)); // SLTU
            put_word(enc_r(7'b0000000,5'd2,5'd1,3'b100,5'd30)); // XOR
            put_word(enc_r(7'b0000000,5'd1,5'd2,3'b101,5'd31)); // SRL
            put_word(enc_r(7'b0100000,5'd1,5'd18,3'b101,5'd24)); // SRA
            put_word(enc_r(7'b0000000,5'd2,5'd1,3'b110,5'd14)); // OR
            put_word(enc_r(7'b0000000,5'd2,5'd1,3'b111,5'd15)); // AND
            put_word(enc_i(12'd0,5'd18,3'b010,5'd16)); // SLTI
            put_word(enc_i(12'd0,5'd18,3'b011,5'd17)); // SLTIU
            put_word(enc_i(12'h055,5'd1,3'b100,5'd13)); // XORI
            put_word(enc_i(12'h080,5'd1,3'b110,5'd12)); // ORI
            put_word(enc_i(12'h007,5'd1,3'b111,5'd11)); // ANDI
            put_word(enc_i(12'h003,5'd1,3'b001,5'd10)); // SLLI
            put_word(enc_i(12'h001,5'd2,3'b101,5'd9)); // SRLI
            put_word(enc_i(12'h402,5'd18,3'b101,5'd8)); // SRAI
            put_word(enc_u(20'habcde,5'd6,7'b0110111)); // LUI
            put_word(enc_u(20'h00001,5'd7,7'b0010111)); // AUIPC

            // Every conditional branch is observed taken and untaken by the
            // instruction-level scoreboard. x1=5 and x2=6 from the prefix.
            branch_case(3'b000,5'd1,5'd1); // BEQ taken
            branch_case(3'b000,5'd1,5'd2); // BEQ untaken
            branch_case(3'b001,5'd1,5'd2); // BNE taken
            branch_case(3'b001,5'd1,5'd1); // BNE untaken
            branch_case(3'b100,5'd1,5'd2); // BLT taken
            branch_case(3'b100,5'd2,5'd1); // BLT untaken
            branch_case(3'b101,5'd2,5'd1); // BGE taken
            branch_case(3'b101,5'd1,5'd2); // BGE untaken
            branch_case(3'b110,5'd1,5'd2); // BLTU taken
            branch_case(3'b110,5'd2,5'd1); // BLTU untaken
            branch_case(3'b111,5'd2,5'd1); // BGEU taken
            branch_case(3'b111,5'd1,5'd2); // BGEU untaken

            // JAL and JALR link/redirect behavior, including wrong-path squash.
            put_word(enc_j(8,5'd22)); // JAL x22,+8
            put_word(enc_i(12'd99,5'd0,3'b000,5'd23)); // wrong-path write
            put_word(enc_i(12'd7,5'd0,3'b000,5'd23)); // JAL target
            jalr_target=(word_index+5)*4;
            put_word(enc_i(jalr_target[11:0],5'd0,3'b000,5'd20)); // construct aligned target
            put_word(enc_s(12'd136,5'd20,5'd0,3'b010)); // save JALR target
            put_word({12'd136,5'd0,3'b010,5'd19,7'b0000011}); // load target
            put_word(enc_i(12'd0,5'd19,3'b000,5'd21,7'b1100111)); // load-to-JALR interlock
            put_word(enc_i(12'd99,5'd0,3'b000,5'd23)); // wrong-path write
            put_word(enc_i(12'd8,5'd0,3'b000,5'd23)); // JALR target

            for (n=0; n<120; n++) begin
                item = rv32i_program_item::type_id::create($sformatf("random_item_%0d",n));
                start_item(item);
                if (!item.randomize()) `uvm_fatal("RAND", "Could not randomize a legal instruction")
                case (item.opclass)
                    3'd0: item.insn = {item.funct7,item.rs2,item.rs1,item.funct3,item.rd,7'b0110011};
                    3'd1: item.insn = {item.imm,item.rs1,item.funct3,item.rd,7'b0010011};
                    3'd2: begin
                        item.rs1 = 0;
                        item.insn = {item.imm,item.rs1,item.funct3,item.rd,7'b0000011};
                    end
                    default: begin
                        if (item.opclass == 3) begin
                            item.rs1 = 0;
                            item.insn = {item.imm[11:5],item.rs2,item.rs1,item.funct3,item.imm[4:0],7'b0100011};
                        end else if (item.opclass == 4) begin
                            item.insn = enc_b(4,item.rs2,item.rs1,item.funct3);
                        end else begin
                            item.insn = enc_j(4,item.rd);
                        end
                    end
                endcase
                item.last = 0;
                finish_item(item);
                word_index++;
            end
            item = rv32i_program_item::type_id::create("end_program");
            start_item(item);
            item.last = 1;
            item.insn = 0;
            finish_item(item);
        endtask
    endclass

    class rv32i_sequencer extends uvm_sequencer #(rv32i_program_item);
        `uvm_component_utils(rv32i_sequencer)
        function new(string name, uvm_component parent); super.new(name,parent); endfunction
    endclass

    class rv32i_driver extends uvm_driver #(rv32i_program_item);
        `uvm_component_utils(rv32i_driver)
        virtual rv32i_uvm_if vif;
        int unsigned load_index;
        function new(string name, uvm_component parent); super.new(name,parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual rv32i_uvm_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF", "rv32i_uvm_if not configured for driver")
        endfunction
        task run_phase(uvm_phase phase);
            rv32i_program_item req;
            load_index = 0;
            begin : driver_loop
            forever begin
                seq_item_port.get_next_item(req);
                if (req.last) begin
                    vif.imem[load_index] = 32'h0000_0000; // illegal stop sentinel
                    seq_item_port.item_done();
                    repeat (3) @(posedge vif.clk);
                    @(negedge vif.clk) vif.rst_n = 1'b1;
                    break;
                end
                if (load_index >= 255) `uvm_fatal("IMEM", "Generated program exceeds instruction memory")
                vif.imem[load_index] = req.insn;
                load_index++;
                seq_item_port.item_done();
            end
            end
        endtask
    endclass

    class rv32i_monitor extends uvm_component;
        `uvm_component_utils(rv32i_monitor)
        virtual rv32i_uvm_if vif;
        uvm_analysis_port #(rv32i_retire_item) ap;
        function new(string name, uvm_component parent); super.new(name,parent); ap=new("ap",this); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual rv32i_uvm_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF", "rv32i_uvm_if not configured for monitor")
        endfunction
        task run_phase(uvm_phase phase);
            rv32i_retire_item item;
            forever begin
                @(posedge vif.clk);
                if (vif.retire_valid) begin
                    item = rv32i_retire_item::type_id::create("retire");
                    item.pc = vif.retire_pc;
                    item.insn = vif.retire_insn;
                    item.rd_we = vif.retire_rd_we;
                    item.rd = vif.retire_rd;
                    item.rd_data = vif.retire_rd_data;
                    item.store_we = vif.retire_store_we;
                    item.store_addr = vif.retire_store_addr;
                    item.store_strb = vif.retire_store_wstrb;
                    item.store_data = vif.retire_store_wdata;
                    ap.write(item);
                end
            end
        endtask
    endclass

    class rv32i_agent extends uvm_agent;
        `uvm_component_utils(rv32i_agent)
        rv32i_sequencer sequencer;
        rv32i_driver driver;
        rv32i_monitor monitor;
        function new(string name, uvm_component parent); super.new(name,parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sequencer=rv32i_sequencer::type_id::create("sequencer",this);
            driver=rv32i_driver::type_id::create("driver",this);
            monitor=rv32i_monitor::type_id::create("monitor",this);
        endfunction
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class rv32i_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(rv32i_scoreboard)
        uvm_analysis_imp #(rv32i_retire_item,rv32i_scoreboard) analysis_export;
        virtual rv32i_uvm_if vif;
        bit [31:0] model_regs [0:31];
        bit [7:0] model_mem [0:4095];
        bit [31:0] model_pc;
        int unsigned retire_count;
        int unsigned class_count [0:5];
        int unsigned instruction_count [0:36];
        int unsigned load_width_count [0:7];
        int unsigned store_width_count [0:2];
        int unsigned branch_taken_count, branch_untaken_count, jump_count;
        int unsigned branch_outcome_count [0:5][0:1];
        bit [31:0] next_pc;
        bit branch_taken;
        bit [31:0] branch_imm, jump_imm;

        function new(string name, uvm_component parent); super.new(name,parent); analysis_export=new("analysis_export",this); endfunction

        function automatic integer instruction_id(input bit [31:0] insn);
            bit [6:0] opcode, f7;
            bit [2:0] f3;
            opcode=insn[6:0]; f3=insn[14:12]; f7=insn[31:25];
            instruction_id=-1;
            case(opcode)
                7'b0110011: case(f3)
                    0: instruction_id=(f7==7'b0100000)?1:0; // SUB/ADD
                    1: instruction_id=2;
                    2: instruction_id=3;
                    3: instruction_id=4;
                    4: instruction_id=5;
                    5: instruction_id=(f7==7'b0100000)?7:6; // SRA/SRL
                    6: instruction_id=8;
                    7: instruction_id=9;
                endcase
                7'b0010011: case(f3)
                    0: instruction_id=10;
                    2: instruction_id=11;
                    3: instruction_id=12;
                    4: instruction_id=13;
                    6: instruction_id=14;
                    7: instruction_id=15;
                    1: instruction_id=16;
                    5: instruction_id=(f7==7'b0100000)?18:17; // SRAI/SRLI
                endcase
                7'b0000011: case(f3)
                    0: instruction_id=19;
                    1: instruction_id=20;
                    2: instruction_id=21;
                    4: instruction_id=22;
                    5: instruction_id=23;
                endcase
                7'b0100011: case(f3)
                    0: instruction_id=24;
                    1: instruction_id=25;
                    2: instruction_id=26;
                endcase
                7'b1100011: case(f3)
                    0: instruction_id=27;
                    1: instruction_id=28;
                    4: instruction_id=29;
                    5: instruction_id=30;
                    6: instruction_id=31;
                    7: instruction_id=32;
                endcase
                7'b1101111: instruction_id=33;
                7'b1100111: instruction_id=34;
                7'b0110111: instruction_id=35;
                7'b0010111: instruction_id=36;
            endcase
        endfunction

        function automatic integer branch_id(input bit [2:0] funct3);
            case(funct3)
                0: branch_id=0;
                1: branch_id=1;
                4: branch_id=2;
                5: branch_id=3;
                6: branch_id=4;
                7: branch_id=5;
                default: branch_id=-1;
            endcase
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual rv32i_uvm_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF", "rv32i_uvm_if not configured for scoreboard")
            foreach (model_regs[i]) model_regs[i]=0;
            foreach (model_mem[i]) model_mem[i]=0;
            foreach (class_count[i]) class_count[i]=0;
            foreach (instruction_count[i]) instruction_count[i]=0;
            foreach (branch_outcome_count[i,j]) branch_outcome_count[i][j]=0;
            foreach (load_width_count[i]) load_width_count[i]=0;
            foreach (store_width_count[i]) store_width_count[i]=0;
            model_pc=0; retire_count=0;
            branch_taken_count=0; branch_untaken_count=0; jump_count=0;
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                @(posedge vif.clk);
                if (!vif.rst_n) begin
                    foreach (model_regs[i]) model_regs[i]=0;
                    model_pc=0;
                end
            end
        endtask

        function void write(rv32i_retire_item t);
            bit [6:0] opcode;
            bit [2:0] f3;
            bit [6:0] f7;
            bit [4:0] rs1,rs2,rd;
            bit [31:0] a,b,imm,expected,addr,word;
            bit expected_we,expected_store;
            bit [3:0] expected_strb;
            int lane;
            int unsigned mem_base;
            int iid, bid;
            opcode=t.insn[6:0]; f3=t.insn[14:12]; f7=t.insn[31:25];
            iid=instruction_id(t.insn);
            if (iid >= 0) instruction_count[iid]++;
            rs1=t.insn[19:15]; rs2=t.insn[24:20]; rd=t.insn[11:7];
            a=(rs1==0)?0:model_regs[rs1]; b=(rs2==0)?0:model_regs[rs2];
            imm={{20{t.insn[31]}},t.insn[31:20]};
            expected=0; expected_we=0; expected_store=0; expected_strb=0; addr=0;
            next_pc=model_pc+4; branch_taken=0; branch_imm=0; jump_imm=0;
            if (t.pc !== model_pc) `uvm_error("PC",$sformatf("retire %0d expected PC %08x got %08x",retire_count,model_pc,t.pc))
            if (t.insn !== vif.imem[t.pc[9:2]])
                `uvm_error("INSN",$sformatf("PC %08x retired instruction %08x differs from loaded word %08x",t.pc,t.insn,vif.imem[t.pc[9:2]]))
            if (opcode==7'b0110011) begin
                class_count[0]++;
                expected_we=1;
                case (f3)
                    0: expected=(f7==7'b0100000)?a-b:a+b;
                    1: expected=a << b[4:0];
                    2: expected=($signed(a)<$signed(b))?1:0;
                    3: expected=(a<b)?1:0;
                    4: expected=a^b;
                    5: expected=(f7==7'b0100000)?model_sra(a,b[4:0]):a >> b[4:0];
                    6: expected=a|b;
                    7: expected=a&b;
                endcase
            end else if (opcode==7'b0010011) begin
                class_count[1]++;
                expected_we=1;
                case(f3)
                    0: expected=a+imm;
                    2: expected=($signed(a)<$signed(imm))?1:0;
                    3: expected=(a<imm)?1:0;
                    4: expected=a^imm;
                    6: expected=a|imm;
                    7: expected=a&imm;
                    1: expected=a << t.insn[24:20];
                    5: expected=(t.insn[30])?model_sra(a,t.insn[24:20]):a >> t.insn[24:20];
                endcase
            end else if (opcode==7'b0000011) begin
                class_count[2]++;
                expected_we=1;
                addr=a+imm; lane=addr[1:0];
                mem_base=addr & 32'hffff_fffc;
                word={model_mem[mem_base+3],model_mem[mem_base+2],
                      model_mem[mem_base+1],model_mem[mem_base]};
                load_width_count[f3]++;
                case(f3)
                    0: expected={{24{word[8*lane+7]}},word[8*lane +: 8]};
                    4: expected={24'b0,word[8*lane +: 8]};
                    1: expected=addr[1]?{{16{word[31]}},word[31:16]}:{{16{word[15]}},word[15:0]};
                    5: expected=addr[1]?{16'b0,word[31:16]}:{16'b0,word[15:0]};
                    2: expected=word;
                    default: `uvm_error("MODEL","Unsupported load funct3 in generated program")
                endcase
            end else if (opcode==7'b0100011) begin
                class_count[3]++;
                expected_store=1;
                imm={{20{t.insn[31]}},t.insn[31:25],t.insn[11:7]};
                addr=a+imm; lane=addr[1:0];
                case(f3)
                    0: begin expected_strb=4'b0001<<lane; expected=({24'b0,b[7:0]}<<(8*lane)); end
                    1: begin expected_strb=4'b0011<<{addr[1],1'b0}; expected=({16'b0,b[15:0]}<<(16*addr[1])); end
                    2: begin expected_strb=4'b1111; expected=b; end
                    default: `uvm_error("MODEL","Unsupported store funct3 in generated program")
                endcase
                store_width_count[f3]++;
            end else if (opcode==7'b1100011) begin
                class_count[4]++;
                bid=branch_id(f3);
                branch_imm={{19{t.insn[31]}},t.insn[31],t.insn[7],t.insn[30:25],t.insn[11:8],1'b0};
                case(f3)
                    0: branch_taken=(a==b);
                    1: branch_taken=(a!=b);
                    4: branch_taken=($signed(a)<$signed(b));
                    5: branch_taken=($signed(a)>=$signed(b));
                    6: branch_taken=(a<b);
                    7: branch_taken=(a>=b);
                    default: `uvm_error("MODEL","Unsupported branch funct3")
                endcase
                if (bid >= 0) branch_outcome_count[bid][branch_taken?1:0]++;
                if (branch_taken) begin next_pc=model_pc+branch_imm; branch_taken_count++; end
                else branch_untaken_count++;
            end else if (opcode==7'b1101111) begin
                class_count[5]++;
                jump_imm={{11{t.insn[31]}},t.insn[31],t.insn[19:12],t.insn[20],t.insn[30:21],1'b0};
                expected_we=1;
                expected=model_pc+4;
                next_pc=model_pc+jump_imm;
                jump_count++;
            end else if (opcode==7'b1100111) begin
                class_count[5]++;
                expected_we=1;
                expected=model_pc+4;
                next_pc=(a+imm)&32'hffff_fffe;
            end else if (opcode==7'b0110111) begin
                expected_we=1;
                expected={t.insn[31:12],12'b0};
            end else if (opcode==7'b0010111) begin
                expected_we=1;
                expected=model_pc+{t.insn[31:12],12'b0};
            end else begin
                `uvm_error("MODEL",$sformatf("Unexpected opcode %02x in generated program",opcode))
            end

            if (t.rd_we !== (expected_we && rd!=0))
                `uvm_error("RDWE",$sformatf("PC %08x expected rd_we=%b got=%b",t.pc,expected_we && rd!=0,t.rd_we))
            if (expected_we && rd!=0) begin
                if (t.rd !== rd || t.rd_data !== expected)
                    `uvm_error("RESULT",$sformatf("PC %08x x%0d expected %08x got x%0d=%08x",t.pc,rd,expected,t.rd,t.rd_data))
                model_regs[rd]=expected;
            end
            if (t.store_we !== expected_store)
                `uvm_error("STORE",$sformatf("PC %08x expected store=%b got=%b",t.pc,expected_store,t.store_we))
            if (expected_store) begin
                if (t.store_addr !== addr || t.store_strb !== expected_strb || t.store_data !== expected)
                    `uvm_error("STORE",$sformatf("PC %08x store addr/data/strobe mismatch",t.pc))
                mem_base=addr & 32'hffff_fffc;
                for (int byte_idx=0;byte_idx<4;byte_idx++)
                    if (expected_strb[byte_idx]) model_mem[mem_base+byte_idx]=expected[8*byte_idx +: 8];
            end
            model_regs[0]=0;
            model_pc=next_pc;
            retire_count++;
        endfunction
    endclass

    class rv32i_env extends uvm_env;
        `uvm_component_utils(rv32i_env)
        rv32i_agent agent;
        rv32i_scoreboard scoreboard;
        function new(string name, uvm_component parent); super.new(name,parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent=rv32i_agent::type_id::create("agent",this);
            scoreboard=rv32i_scoreboard::type_id::create("scoreboard",this);
        endfunction
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.ap.connect(scoreboard.analysis_export);
        endfunction
    endclass

    class rv32i_uvm_random_test extends uvm_test;
        `uvm_component_utils(rv32i_uvm_random_test)
        rv32i_env env;
        virtual rv32i_uvm_if vif;
        function new(string name, uvm_component parent); super.new(name,parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual rv32i_uvm_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF","rv32i_uvm_if not configured for test")
            env=rv32i_env::type_id::create("env",this);
        endfunction
        task run_phase(uvm_phase phase);
            rv32i_random_sequence seq;
            uvm_report_server report_server;
            int isa_bins, branch_bins;
            phase.raise_objection(this);
            seq=rv32i_random_sequence::type_id::create("seq");
            seq.start(env.agent.sequencer);
            wait(vif.stop===1'b1);
            repeat(5) @(posedge vif.clk);
            #1;
            if (vif.stop_cause !== 2'd1 || vif.stop_pc !== env.scoreboard.model_pc)
                `uvm_error("STOP",$sformatf("Expected illegal stop at model PC %08x, got cause=%0d pc=%08x",env.scoreboard.model_pc,vif.stop_cause,vif.stop_pc))
            if (env.scoreboard.retire_count < 100)
                `uvm_error("COUNT",$sformatf("Too few retirements: %0d",env.scoreboard.retire_count))
            if (vif.observed_midrun_resets != 1)
                `uvm_error("RESET",$sformatf("Expected one injected mid-run reset, observed %0d",vif.observed_midrun_resets))
            if (env.scoreboard.branch_taken_count == 0 || env.scoreboard.branch_untaken_count == 0 || env.scoreboard.jump_count == 0)
                `uvm_error("COVER","Taken/untaken branch and jump coverage must each be nonzero")
            if (vif.observed_stalls == 0 || vif.forward_exmem_a == 0 || vif.forward_exmem_b == 0 ||
                vif.forward_memwb_a == 0 || vif.forward_memwb_b == 0 || vif.observed_redirects < 3)
                `uvm_error("COVER","Stall, forwarding-port/source, and redirect bins must be hit")
            if (vif.class_forward_count[0] == 0 || vif.class_forward_count[1] == 0 ||
                vif.class_forward_count[3] == 0 || vif.class_forward_count[4] == 0 ||
                vif.class_forward_count[5] == 0)
                `uvm_error("HAZARD_COVER","R/I/store/branch/jump forwarding class bins must be hit")
            if (vif.class_stall_count[1] == 0 || vif.class_stall_count[3] == 0 ||
                vif.class_stall_count[4] == 0 || vif.class_stall_count[5] == 0)
                `uvm_error("HAZARD_COVER","I/store/branch/JALR load-use consumer bins must be hit")
            if (vif.branch_fwd_taken == 0 || vif.branch_fwd_untaken == 0 ||
                vif.branch_no_fwd_taken == 0 || vif.branch_no_fwd_untaken == 0)
                `uvm_error("BRANCH_HAZARD_COVER","Taken/untaken x forwarded/unforwarded branch bins must be hit")
            if (env.scoreboard.load_width_count[0] == 0 || env.scoreboard.load_width_count[1] == 0 ||
                env.scoreboard.load_width_count[2] == 0 || env.scoreboard.load_width_count[4] == 0 ||
                env.scoreboard.load_width_count[5] == 0 || env.scoreboard.store_width_count[0] == 0 ||
                env.scoreboard.store_width_count[1] == 0 || env.scoreboard.store_width_count[2] == 0)
                `uvm_error("COVER","At least one load/store width funct3 bin was not covered")
            if (vif.observed_write_count != env.scoreboard.class_count[3])
                `uvm_error("FLUSH",$sformatf("Observed %0d memory writes for %0d retired stores; a wrong-path store may have escaped",vif.observed_write_count,env.scoreboard.class_count[3]))
            for (int i=0;i<6;i++)
                if (env.scoreboard.class_count[i] == 0) `uvm_error("COVER",$sformatf("Instruction class %0d not covered",i))
            isa_bins=0;
            for (int i=0;i<37;i++) begin
                if (env.scoreboard.instruction_count[i] != 0) isa_bins++;
                else `uvm_error("ISA_COVER",$sformatf("Supported instruction bin %0d was not hit",i))
            end
            branch_bins=0;
            for (int branch=0;branch<6;branch++)
                for (int outcome=0;outcome<2;outcome++) begin
                    if (env.scoreboard.branch_outcome_count[branch][outcome] != 0) branch_bins++;
                    else `uvm_error("BRANCH_COVER",$sformatf("Branch condition %0d outcome %0d was not hit",branch,outcome))
                end
            `uvm_info("COVER",$sformatf("retired=%0d ISA=%0d/37 branch_condition_outcomes=%0d/12 R/I/L/S/B/J=%0d/%0d/%0d/%0d/%0d/%0d stalls=%0d reset=%0d branch_fwd(T/U)=%0d/%0d branch_no_fwd(T/U)=%0d/%0d class_fwd(R/I/L/S/B/J)=%0d/%0d/%0d/%0d/%0d/%0d class_stall(R/I/L/S/B/J)=%0d/%0d/%0d/%0d/%0d/%0d fwd_exmem(A/B)=%0d/%0d fwd_memwb(A/B)=%0d/%0d redirects=%0d",env.scoreboard.retire_count,isa_bins,branch_bins,env.scoreboard.class_count[0],env.scoreboard.class_count[1],env.scoreboard.class_count[2],env.scoreboard.class_count[3],env.scoreboard.class_count[4],env.scoreboard.class_count[5],vif.observed_stalls,vif.observed_midrun_resets,vif.branch_fwd_taken,vif.branch_fwd_untaken,vif.branch_no_fwd_taken,vif.branch_no_fwd_untaken,vif.class_forward_count[0],vif.class_forward_count[1],vif.class_forward_count[2],vif.class_forward_count[3],vif.class_forward_count[4],vif.class_forward_count[5],vif.class_stall_count[0],vif.class_stall_count[1],vif.class_stall_count[2],vif.class_stall_count[3],vif.class_stall_count[4],vif.class_stall_count[5],vif.forward_exmem_a,vif.forward_exmem_b,vif.forward_memwb_a,vif.forward_memwb_b,vif.observed_redirects),UVM_LOW)
            report_server=uvm_report_server::get_server();
            if (report_server.get_severity_count(UVM_ERROR)==0 && report_server.get_severity_count(UVM_FATAL)==0)
                $display("PASS: UVM reference scoreboard; %0d instructions retired",env.scoreboard.retire_count);
            else
                $display("FAIL: UVM reference scoreboard reported %0d error(s)",report_server.get_severity_count(UVM_ERROR));
            phase.drop_objection(this);
        endtask
    endclass
endpackage

`default_nettype wire
